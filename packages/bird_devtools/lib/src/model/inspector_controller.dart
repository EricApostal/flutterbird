import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import '../protocol/rdp_transport.dart';
import '../util/css_color.dart';
import 'dom.dart';
import 'session.dart';
import 'styles.dart';
import 'tool_controller.dart';

class UsedFont {
  const UsedFont(this.name, this.weight);
  final String name;
  final int weight;
}

class FlexItemInfo {
  const FlexItemInfo(this.nodeActor, this.sizing, this.properties);
  final String nodeActor;
  final Map<String, Object?> sizing;
  final Map<String, Object?> properties;
}

class FlexContainerInfo {
  const FlexContainerInfo(this.nodeActor, this.properties, this.items);
  final String nodeActor;
  final Map<String, Object?> properties;
  final List<FlexItemInfo> items;
}

class GridInfo {
  const GridInfo(this.nodeActor, this.columns, this.rows);
  final String nodeActor;
  final int columns;
  final int rows;
}

/// One edit made through the tools, for the Changes view.
class StyleChange {
  StyleChange(this.source, this.selector, this.property);
  final String source;
  final String selector;
  final String property;

  /// The declaration as the page had it, and as it is now. Null for none.
  String? before;
  String? after;
}

class SearchState {
  const SearchState(this.query, this.matches, this.index);
  final String query;
  final List<List<int>> matches;
  final int index;
}

/// The elements pseudo-classes can be forced on.
const List<String> forcePseudoClasses = [
  'hover',
  'active',
  'focus',
  'focus-visible',
  'focus-within',
  'visited',
  'target',
];

class InspectorController extends ToolController {
  InspectorController(super.session);

  String? _walker;
  String? _pageStyle;
  String? _highlighter;
  String? _layoutInspector;
  String? _flexHighlighter;
  String? _gridHighlighter;
  void Function()? _walkerListener;
  int _generation = 0;

  DomNode? root;
  final Map<String, DomNode> _nodes = {};
  final Set<String> expanded = {};
  DomNode? selected;

  /// Nodes that changed a moment ago, which the markup view flashes.
  final Set<String> flashing = {};

  /// Counts up each time the selected node should be scrolled into view.
  int revealSerial = 0;

  /// Counts up with every change to the shape of the tree.
  int treeRevision = 0;

  bool picking = false;
  DomNode? pickerHover;

  // What the sidebar shows of the selected element.
  List<AppliedRule> rules = [];
  bool rulesLoading = false;
  List<MapEntry<String, String>> computed = [];
  Map<String, Object?> boxModel = const {};
  List<UsedFont> fonts = [];
  FlexContainerInfo? flexContainer;
  FlexContainerInfo? parentFlexContainer;
  List<GridInfo> grids = [];
  final Set<String> highlightedGrids = {};
  bool flexHighlighted = false;

  /// Declarations unticked in the rules view, by their rule.
  final Map<String, List<(int, CssDeclaration)>> _disabled = {};
  final List<StyleChange> changes = [];
  final Map<String, Set<String>> _lockedPseudoClasses = {};
  String ruleError = '';

  SearchState? search;
  bool searching = false;

  String? _restoreSelector;

  bool get showBrowserStyles => session.settings.flag('inspector.userAgent');

  // ------------------------------------------------------------ lifecycle

  /// The address of the document the tree is of.
  String _documentUrl = '';

  static String _withoutFragment(String url) => url.split('#').first;

  @override
  void onTargetAvailable(DevToolsTarget target) {
    _documentUrl = target.url;
    _attach(target);
  }

  @override
  void onWillNavigate(String url) {
    // The selection is only looked for again in the same document.
    if (_withoutFragment(url) != _withoutFragment(_documentUrl)) {
      _restoreSelector = null;
    }
  }

  @override
  void onTargetDestroyed() {
    // The same element is looked for in the page that comes next.
    _restoreSelector = selectedElementSelector ?? _restoreSelector;
    _generation++;
    _walkerListener?.call();
    _walkerListener = null;
    _walker = _pageStyle = _highlighter = _layoutInspector = null;
    _flexHighlighter = _gridHighlighter = null;
    root = null;
    _nodes.clear();
    expanded.clear();
    selected = null;
    picking = false;
    pickerHover = null;
    _clearSidebar();
    _disabled.clear();
    highlightedGrids.clear();
    _lockedPseudoClasses.clear();
    flexHighlighted = false;
    search = null;
    treeRevision++;
    changed();
  }

  void _clearSidebar() {
    rules = [];
    computed = [];
    boxModel = const {};
    fonts = [];
    flexContainer = null;
    parentFlexContainer = null;
    grids = [];
  }

  Future<void> _attach(DevToolsTarget target) async {
    final generation = ++_generation;
    bool stale() => generation != _generation || isDisposed;
    // A page that is still loading has no document to walk yet.
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final response = await session.connection.request(
          target.inspectorActor,
          'getWalker',
          const {},
          const Duration(seconds: 5),
        );
        if (stale()) return;
        final walker = response.obj('walker');
        final actor = walker.str('actor');
        _walker = actor;
        _walkerListener?.call();
        _walkerListener = session.connection.listen(actor, _onWalkerPacket);

        _pageStyle = (await session.connection.request(
          target.inspectorActor,
          'getPageStyle',
        )).obj('pageStyle').str('actor');
        _highlighter = await _makeHighlighter(target, 'BoxModelHighlighter');
        _flexHighlighter = await _makeHighlighter(target, 'FlexboxHighlighter');
        _gridHighlighter = await _makeHighlighter(target, 'CssGridHighlighter');
        _layoutInspector = (await session.connection.request(
          actor,
          'getLayoutInspector',
        )).obj('actor').str('actor');
        if (stale()) return;
        await _setRoot(walker.mapOrNull('root'));
        return;
      } on RdpError catch (error) {
        if (stale() || error.isClosed || error.isUnknownActor) return;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (stale()) return;
      }
    }
  }

  Future<String> _makeHighlighter(DevToolsTarget target, String type) async {
    final response = await session.connection.request(
      target.inspectorActor,
      'getHighlighterByType',
      {'typeName': type},
    );
    return response.obj('highlighter').str('actor');
  }

  /// Takes the tools' marks off the page.
  void release() {
    if (picking) stopPicker();
    unhighlight();
    for (final highlighter in [_flexHighlighter, _gridHighlighter]) {
      if (highlighter != null) {
        session.connection.notify(highlighter, 'hide');
      }
    }
  }

  // ------------------------------------------------------------ the tree

  DomNode? nodeFor(String actor) => _nodes[actor];

  DomNode _adopt(Map<String, Object?> form, DomNode? parent) {
    final actor = form.str('actor');
    final existing = _nodes[actor];
    if (existing != null) {
      existing
        ..update(form)
        ..parent = parent;
      return existing;
    }
    return _nodes[actor] = DomNode(form)..parent = parent;
  }

  Future<void> _setRoot(Map<String, Object?>? form) async {
    _nodes.clear();
    expanded.clear();
    selected = null;
    root = form == null ? null : _adopt(form, null);
    treeRevision++;
    final document = root;
    if (document == null) {
      changed();
      return;
    }
    await loadChildren(document);
    final html = _elementChild(document, 'html');
    DomNode? choose;
    if (html != null) {
      await expand(html);
      final body = _elementChild(html, 'body');
      if (body != null) {
        await expand(body);
        choose = body;
      }
      choose ??= html;
    }
    final restore = _restoreSelector;
    if (restore != null && restore.isNotEmpty) {
      final found = await _find(restore);
      if (found != null) choose = found;
    }
    if (choose != null && selected == null) select(choose, reveal: true);
    changed();
  }

  DomNode? _elementChild(DomNode node, String tag) {
    for (final child in node.children ?? const <DomNode>[]) {
      if (child.isElement && child.tag.toLowerCase() == tag) return child;
    }
    return null;
  }

  /// A node's children, without the elements the tools themselves put there.
  Future<List<DomNode>> loadChildren(DomNode node, {bool reload = false}) async {
    final held = node.children;
    if (held != null && !reload) return held;
    final walker = _walker;
    if (walker == null) return const [];
    try {
      final response = await session.connection.request(walker, 'children', {
        'node': node.actor,
      });
      final children = [
        for (final form in response.maps('nodes')) _adopt(form, node),
      ]..removeWhere((child) => child.attribute('data-fb-devtools') != null);
      node.children = children;
      treeRevision++;
      // A lone text child is shown on its element's line.
      await Future.wait([
        for (final child in children)
          if (child.isElement && child.childCount == 1 && child.children == null)
            loadChildren(child),
      ]);
      return children;
    } on RdpError {
      return const [];
    }
  }

  Future<void> expand(DomNode node) async {
    await loadChildren(node);
    expanded.add(node.actor);
    treeRevision++;
    changed();
  }

  void collapse(DomNode node) {
    expanded.remove(node.actor);
    treeRevision++;
    changed();
  }

  /// Opens a node and everything under it, as Alt-clicking its arrow does.
  Future<void> expandAll(DomNode node) async {
    var budget = 600;
    Future<void> visit(DomNode node) async {
      if (budget-- <= 0 || node.childCount == 0 || node.inlineText != null) {
        return;
      }
      await loadChildren(node);
      if (node.inlineText != null) return;
      expanded.add(node.actor);
      for (final child in node.children ?? const <DomNode>[]) {
        await visit(child);
      }
    }

    await visit(node);
    treeRevision++;
    changed();
  }

  bool isExpandable(DomNode node) =>
      node.childCount > 0 && node.inlineText == null;

  void select(DomNode node, {bool reveal = false}) {
    // Opens what holds the node, so that it can be seen.
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      expanded.add(parent.actor);
    }
    if (reveal) revealSerial++;
    if (selected == node) {
      changed();
      return;
    }
    selected = node;
    ruleError = '';
    treeRevision++;
    changed();
    refreshStyles();
  }

  /// The element the sidebar is about: text answers for its element.
  DomNode? get selectedElement {
    var node = selected;
    while (node != null && !node.isElement && !node.isPseudoElement) {
      node = node.parent;
    }
    return node;
  }

  String? get selectedElementSelector {
    var node = selected;
    while (node != null && !node.isElement) {
      node = node.parent;
    }
    final selector = node?.cssSelector;
    return selector == null || selector.isEmpty ? null : selector;
  }

  // ------------------------------------------------------------ walker events

  void _onWalkerPacket(RdpPacket packet) {
    switch (packet['type']) {
      case 'newMutations':
        _readMutations();
      case 'root-destroyed':
        // This comes before the page says it is navigating.
        _restoreSelector = selectedElementSelector ?? _restoreSelector;
        root = null;
        _nodes.clear();
        expanded.clear();
        selected = null;
        _clearSidebar();
        treeRevision++;
        changed();
      case 'root-available':
        _setRoot(packet.mapOrNull('node'));
      case 'pickerNodeHovered':
        _onPicker(packet.obj('node'), done: false);
      case 'pickerNodePicked':
        _onPicker(packet.obj('node'), done: true);
      case 'pickerNodePreviewed':
        _onPicker(packet.obj('node'), done: false);
      case 'pickerNodeCanceled':
        picking = false;
        pickerHover = null;
        changed();
    }
  }

  Future<void> _readMutations() async {
    final walker = _walker;
    if (walker == null) return;
    final RdpPacket response;
    try {
      response = await session.connection.request(walker, 'getMutations');
    } on RdpError {
      return;
    }
    if (walker != _walker) return;
    final reload = <DomNode>{};
    var touchesSelection = false;
    var touchesStyles = false;
    for (final mutation in response.maps('mutations')) {
      final node = _nodes[mutation.str('target')];
      if (node == null) continue;
      if (node == selectedElement) touchesSelection = true;
      switch (mutation.str('type')) {
        case 'attributes':
          final name = mutation.str('attributeName');
          if (name.startsWith('data-fb-')) continue;
          final value = mutation.strOrNull('newValue');
          final attributes = node.attributes.toList();
          final index = attributes.indexWhere((a) => a.name == name);
          if (value == null) {
            if (index >= 0) attributes.removeAt(index);
          } else if (index >= 0) {
            attributes[index] = DomAttribute(name, value);
          } else {
            attributes.add(DomAttribute(name, value));
          }
          node.attributes = attributes;
          touchesStyles = true;
          _flash(node);
        case 'characterData':
          final value = mutation.strOrNull('newValue');
          if (value != null) node.nodeValue = value;
          _flash(node);
        case 'childList':
          node.childCount = mutation.integer('numChildren', node.childCount);
          if (node.children != null || node.childCount == 1) reload.add(node);
          _flash(node);
      }
    }
    for (final node in reload) {
      await loadChildren(node, reload: true);
    }
    // The selection may have been taken out of the page.
    if (selected case final current?) {
      bool attached(DomNode node) {
        if (node.isDocument) return true;
        final parent = node.parent;
        return parent != null &&
            (parent.children?.contains(node) ?? false) &&
            attached(parent);
      }

      if (!attached(current)) {
        var survivor = current.parent;
        while (survivor != null && !attached(survivor)) {
          survivor = survivor.parent;
        }
        selected = null;
        if (survivor != null && !survivor.isDocument) {
          select(survivor);
        }
      }
    }
    treeRevision++;
    changed();
    if (touchesSelection || touchesStyles) _scheduleStyleRefresh();
  }

  Timer? _styleRefresh;

  void _scheduleStyleRefresh() {
    _styleRefresh?.cancel();
    _styleRefresh = Timer(const Duration(milliseconds: 250), refreshStyles);
  }

  void _flash(DomNode node) {
    flashing.add(node.actor);
    Timer(const Duration(milliseconds: 900), () {
      if (flashing.remove(node.actor)) changed();
    });
  }

  // ------------------------------------------------------------ finding nodes

  /// Puts a node the server described apart from the tree into its place.
  Future<DomNode?> _resolve(Map<String, Object?> disconnected) async {
    final target = disconnected.obj('node');
    final actor = target.str('actor');
    if (actor.isEmpty) return null;
    final chain = [
      ...disconnected.maps('newParents').reversed.map((p) => p.str('actor')),
      actor,
    ];
    var node = root;
    if (node == null) return null;
    for (final next in chain) {
      var children = await loadChildren(node!);
      var child = children.where((c) => c.actor == next).firstOrNull;
      if (child == null) {
        children = await loadChildren(node, reload: true);
        child = children.where((c) => c.actor == next).firstOrNull;
      }
      if (child == null) return null;
      node = child;
    }
    return node;
  }

  /// Walks down from the root element by element positions.
  Future<DomNode?> nodeAtPath(List<int> path) async {
    final document = root;
    if (document == null) return null;
    await loadChildren(document);
    var node = _elementChild(document, 'html');
    for (final index in path) {
      if (node == null) return null;
      final children = await loadChildren(node);
      final elements = children.where((c) => c.isElement).toList();
      if (index < 0 || index >= elements.length) return null;
      node = elements[index];
    }
    return node;
  }

  static const String _pathOf =
      'const pathOf = element => { const path = []; '
      'for (let node = element; node && node !== document.documentElement && node.parentElement; node = node.parentElement) '
      'path.unshift(Array.prototype.indexOf.call(node.parentElement.children, node)); return path; };';

  Future<DomNode?> _find(String selector) async {
    try {
      final result = await session.runInPage(
        '$_pathOf const element = document.querySelector(${jsonEncode(selector)});'
        // The tools' own elements do not count among an element's children.
        'return element ? pathOf(element) : null;',
      );
      if (result is! List) return null;
      return await nodeAtPath([for (final step in result) (step as num).toInt()]);
    } catch (_) {
      return null;
    }
  }

  Future<void> selectPath(List<int> path) async {
    final node = await nodeAtPath(path);
    if (node == null) return;
    select(node, reveal: true);
  }

  /// Shows the element a value in the console stands for.
  Future<void> selectContentDomReference(Map<String, Object?> reference) async {
    final node = await resolveContentDomReference(reference);
    if (node != null) select(node, reveal: true);
  }

  Future<DomNode?> resolveContentDomReference(
    Map<String, Object?> reference,
  ) async {
    // Asked for as the toolbox opens, there may be no walker for a moment.
    for (var attempt = 0; attempt < 40; attempt++) {
      if (_walker != null && root != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (isDisposed) return null;
    }
    final walker = _walker;
    if (walker == null) return null;
    try {
      final response = await session.connection.request(
        walker,
        'getNodeActorFromContentDomReference',
        {'contentDomReference': reference},
      );
      final front = response.mapOrNull('nodeFront');
      return front == null ? null : await _resolve(front);
    } on RdpError {
      return null;
    }
  }

  // ------------------------------------------------------------ highlighting

  void highlight(DomNode node) {
    final highlighter = _highlighter;
    if (highlighter == null || picking) return;
    var target = node;
    while (!target.isElement && !target.isPseudoElement) {
      final parent = target.parent;
      if (parent == null) return;
      target = parent;
    }
    session.connection.notify(highlighter, 'show', {'node': target.actor});
  }

  void unhighlight() {
    final highlighter = _highlighter;
    if (highlighter != null) session.connection.notify(highlighter, 'hide');
  }

  /// Highlights the element a console value stands for.
  Future<void> highlightContentDomReference(
    Map<String, Object?> reference,
  ) async {
    final node = await resolveContentDomReference(reference);
    if (node != null) highlight(node);
  }

  // ------------------------------------------------------------ the picker

  Future<void> startPicker() async {
    final walker = _walker;
    if (walker == null || picking) return;
    picking = true;
    changed();
    try {
      await session.connection.request(walker, 'pick');
    } on RdpError {
      picking = false;
      changed();
    }
  }

  Future<void> stopPicker() async {
    final walker = _walker;
    if (walker == null || !picking) return;
    picking = false;
    pickerHover = null;
    changed();
    session.connection.notify(walker, 'cancelPick');
  }

  void togglePicker() => picking ? stopPicker() : startPicker();

  Future<void> _onPicker(
    Map<String, Object?> disconnected, {
    required bool done,
  }) async {
    final node = await _resolve(disconnected);
    if (done) {
      picking = false;
      pickerHover = null;
      session.selectTool('inspector');
    } else {
      pickerHover = node;
    }
    if (node != null) {
      if (done) {
        select(node, reveal: true);
      } else {
        for (var p = node.parent; p != null; p = p.parent) {
          expanded.add(p.actor);
        }
        revealSerial++;
        treeRevision++;
      }
    }
    changed();
  }

  // ------------------------------------------------------------ search

  /// Finds the elements a selector matches, or whose markup or text holds the
  /// words. Calling it again with the same words moves to the next one.
  Future<void> runSearch(String query, {bool backwards = false}) async {
    final trimmed = query.trim();
    final current = search;
    if (trimmed.isEmpty) {
      search = null;
      changed();
      return;
    }
    if (current != null && current.query == trimmed) {
      if (current.matches.isEmpty) return;
      final index =
          (current.index + (backwards ? -1 : 1)) % current.matches.length;
      search = SearchState(trimmed, current.matches, index);
      changed();
      await selectPath(current.matches[index]);
      return;
    }
    searching = true;
    changed();
    try {
      final result = await session.runInPage(
        '$_pathOf const query = ${jsonEncode(trimmed)}; const needle = query.toLowerCase();'
        'let bySelector = new Set(); try { bySelector = new Set(document.querySelectorAll(query)); } catch (error) {}'
        'const found = [];'
        'for (const element of document.querySelectorAll("*")) {'
        '  if (found.length >= 500) break;'
        '  if (element.hasAttribute("data-fb-devtools")) continue;'
        '  const matches = bySelector.has(element) || element.localName.includes(needle) ||'
        '    Array.from(element.attributes).some(a => a.name.includes(needle) || a.value.toLowerCase().includes(needle)) ||'
        '    Array.from(element.childNodes).some(n => (n.nodeType === 3 || n.nodeType === 8) && n.textContent.toLowerCase().includes(needle));'
        '  if (matches) found.push(pathOf(element));'
        '}'
        'return found;',
      );
      final matches = [
        if (result is List)
          for (final path in result)
            if (path is List) [for (final step in path) (step as num).toInt()],
      ];
      search = SearchState(trimmed, matches, 0);
      if (matches.isNotEmpty) await selectPath(matches.first);
    } catch (_) {
      search = SearchState(trimmed, const [], 0);
    }
    searching = false;
    changed();
  }

  // ------------------------------------------------------------ editing the DOM

  Future<void> _modify(DomNode node, List<Map<String, Object?>> changes) async {
    try {
      await session.connection.request(node.actor, 'modifyAttributes', {
        'modifications': changes,
      });
    } on RdpError {
      // The node is gone.
    }
  }

  Future<void> setAttribute(DomNode node, String name, String value) => _modify(
    node,
    [
      {'attributeName': name, 'newValue': value},
    ],
  );

  Future<void> removeAttribute(DomNode node, String name) => _modify(node, [
    {'attributeName': name},
  ]);

  static final RegExp _attributePattern = RegExp(
    '([^\\s"\'=<>/]+)(?:\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+)))?',
  );

  static List<DomAttribute> parseAttributes(String text) => [
    for (final match in _attributePattern.allMatches(text))
      DomAttribute(
        match.group(1)!,
        _unescape(match.group(2) ?? match.group(3) ?? match.group(4) ?? ''),
      ),
  ];

  static String _unescape(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  /// Replaces attribute [name] with what [text] writes, which may be nothing,
  /// or several attributes.
  Future<void> replaceAttribute(DomNode node, String name, String text) {
    final next = parseAttributes(text);
    return _modify(node, [
      {'attributeName': name},
      for (final attribute in next)
        {'attributeName': attribute.name, 'newValue': attribute.value},
    ]);
  }

  Future<void> addAttributes(DomNode node, String text) async {
    final next = parseAttributes(text);
    if (next.isEmpty) return;
    await _modify(node, [
      for (final attribute in next)
        {'attributeName': attribute.name, 'newValue': attribute.value},
    ]);
  }

  Future<void> _walkerAction(
    String type,
    Map<String, Object?> parameters,
  ) async {
    final walker = _walker;
    if (walker == null) return;
    try {
      await session.connection.request(
        walker,
        type,
        parameters,
        const Duration(seconds: 5),
      );
    } on RdpError {
      // The node is gone, or the engine refused.
    }
  }

  Future<void> setTextContent(DomNode node, String text) async {
    try {
      await session.connection.request(node.actor, 'setNodeValue', {
        'value': text,
      });
    } on RdpError {
      // The node is gone.
    }
  }

  Future<void> setTagName(DomNode node, String tag) =>
      _walkerAction('editTagName', {'node': node.actor, 'tagName': tag});

  bool canModify(DomNode node) =>
      !node.isDocument &&
      !node.isPseudoElement &&
      !(node.isElement && const ['html', 'head', 'body'].contains(node.tag));

  Future<void> removeNode(DomNode node) async {
    if (!canModify(node)) return;
    final parent = node.parent;
    final siblings = parent?.children ?? const <DomNode>[];
    final index = siblings.indexOf(node);
    final next = index >= 0 && index + 1 < siblings.length
        ? siblings[index + 1]
        : index > 0
        ? siblings[index - 1]
        : parent;
    if (next != null) select(next);
    await _walkerAction('removeNode', {'node': node.actor});
    if (parent != null) await loadChildren(parent, reload: true);
    changed();
  }

  Future<void> duplicateNode(DomNode node) =>
      _walkerAction('duplicateNode', {'node': node.actor});

  /// Adds an empty `<div>` as the node's last child.
  Future<void> addChild(DomNode node) async {
    await _walkerAction('insertAdjacentHTML', {
      'node': node.actor,
      'value': '<div></div>',
      'position': 'beforeEnd',
    });
    await loadChildren(node, reload: true);
    await expand(node);
  }

  Future<void> moveNode(DomNode node, DomNode parent, DomNode? before) async {
    for (DomNode? p = parent; p != null; p = p.parent) {
      if (p == node) return;
    }
    await _walkerAction('insertBefore', {
      'node': node.actor,
      'parent': parent.actor,
      'sibling': ?before?.actor,
    });
  }

  Future<String> html(DomNode node, {bool inner = false}) async {
    final walker = _walker;
    if (walker == null) return '';
    try {
      final response = await session.connection.request(
        walker,
        inner ? 'innerHTML' : 'outerHTML',
        {'node': node.actor},
        const Duration(seconds: 5),
      );
      return response.str('value');
    } on RdpError {
      return '';
    }
  }

  Future<void> setOuterHtml(DomNode node, String value) =>
      _walkerAction('setOuterHTML', {'node': node.actor, 'value': value});

  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> scrollIntoView(DomNode node) async {
    final selector = node.cssSelector;
    try {
      await session.runInPage(
        'document.querySelector(${jsonEncode(selector)})?.scrollIntoView({ block: "center" }); return true;',
      );
      highlight(node);
    } catch (_) {
      // Nothing to scroll to.
    }
  }

  // ------------------------------------------------------------ the sidebar

  int _styleGeneration = 0;

  Future<void> refreshStyles() async {
    final pageStyle = _pageStyle;
    final element = selectedElement;
    final generation = ++_styleGeneration;
    bool stale() => generation != _styleGeneration || isDisposed;
    if (pageStyle == null || element == null) {
      _clearSidebar();
      changed();
      return;
    }
    rulesLoading = true;
    final connection = session.connection;
    Future<RdpPacket?> ask(
      String actor,
      String type, [
      Map<String, Object?> parameters = const {},
    ]) async {
      try {
        return await connection.request(
          actor,
          type,
          parameters,
          const Duration(seconds: 6),
        );
      } on RdpError {
        return null;
      }
    }

    final node = {'node': element.actor};
    final applied = ask(pageStyle, 'getApplied', {
      ...node,
      'inherited': true,
      'matchedSelectors': true,
      'filter': showBrowserStyles ? 'ua' : 'user',
    });
    final computedStyle = ask(pageStyle, 'getComputed', node);
    final layout = ask(pageStyle, 'getLayout', {...node, 'autoMargins': true});
    final usedFonts = ask(pageStyle, 'getUsedFontFaces', node);

    final appliedResponse = await applied;
    if (stale()) return;
    final parsed = [
      for (final entry in appliedResponse?.maps('entries') ??
              const <Map<String, Object?>>[])
        AppliedRule.parse(entry),
    ];
    // The element's own style is shown even while it is empty.
    if (element.isElement && !parsed.any((r) => r.isElementStyle && r.inheritedFrom == null)) {
      parsed.insert(
        0,
        AppliedRule(
          actor: '',
          isElementStyle: true,
          selectors: const [],
          matchedSelectors: const {},
          declarations: [],
          cssText: '',
          authoredText: '',
        ),
      );
    }
    await _locateRules(parsed);
    if (stale()) return;
    for (final rule in parsed) {
      for (final (index, declaration)
          in _disabled[rule.identity] ?? <(int, CssDeclaration)>[]) {
        rule.declarations.insert(
          index.clamp(0, rule.declarations.length),
          declaration,
        );
      }
    }
    parsed.removeWhere((rule) => !ruleReachesElement(rule));
    markOverriddenDeclarations(parsed);
    rules = parsed;
    rulesLoading = false;
    changed();

    final computedResponse = await computedStyle;
    final layoutResponse = await layout;
    final fontResponse = await usedFonts;
    if (stale()) return;
    computed = [
      for (final entry
          in computedResponse?.obj('computed').entries ??
              const <MapEntry<String, Object?>>[])
        if (entry.value case final Map<String, Object?> property)
          MapEntry(entry.key, '${property['value'] ?? ''}'),
    ]..sort((a, b) => a.key.compareTo(b.key));
    boxModel = layoutResponse ?? const {};
    fonts = [
      for (final font in fontResponse?.maps('fontFaces') ??
              const <Map<String, Object?>>[])
        UsedFont(font.str('name'), font.integer('weight')),
    ];
    changed();
    await _refreshLayout(element, generation);
  }

  /// Finds the sheet and line of the rules the server did not place. It can
  /// only be done by finding each rule's text among the page's style sheets.
  Future<void> _locateRules(List<AppliedRule> rules) async {
    final sheets = session.styleEditor.sheets;
    final unplaced = [
      for (final rule in rules)
        if (!rule.isElementStyle && !rule.isSystem && rule.styleSheetId == null) rule,
    ];
    if (unplaced.isNotEmpty && sheets.isNotEmpty) {
      try {
        final result = await session.runInPage(
          'const wanted = ${jsonEncode([for (final rule in unplaced) rule.cssText])};'
          'const found = wanted.map(() => null);'
          'const owned = node => node && node.hasAttribute && (node.hasAttribute("data-fb-devtools") || node.hasAttribute("data-fb-new"));'
          'let inline = 0;'
          'for (const sheet of document.styleSheets) {'
          '  if (owned(sheet.ownerNode)) continue;'
          '  const place = sheet.href ? { href: sheet.href } : { inline: inline++ };'
          '  const visit = list => { for (const rule of list) {'
          '    wanted.forEach((text, i) => { if (rule.cssText === text) found[i] = place; });'
          '    if (rule.styleSheet) { try { visit(rule.styleSheet.cssRules); } catch (e) {} }'
          '    if (rule.cssRules) visit(rule.cssRules); } };'
          '  try { visit(sheet.cssRules); } catch (e) {}'
          '}'
          'return found;',
          timeout: const Duration(seconds: 4),
        );
        if (result is List && result.length == unplaced.length) {
          for (final (index, place) in result.indexed) {
            if (place is! Map<String, Object?>) continue;
            final href = place.str('href');
            final sheet = sheets
                .where((s) => href.isNotEmpty ? s.href == href : !s.isNew && s.inlineOrdinal == place.integer('inline', -1))
                .firstOrNull;
            unplaced[index].styleSheetId = sheet?.resourceId;
          }
        }
      } catch (_) {
        // The rules are shown without a place.
      }
    }
    for (final rule in rules) {
      final id = rule.styleSheetId;
      final sheet = id == null ? null : session.styleEditor.sheetById(id);
      if (sheet == null || rule.selectors.isEmpty) continue;
      await session.styleEditor.load(sheet);
      rule.sourceLine = _lineOfSelector(sheet.originalText ?? '', rule.selectorText);
    }
  }

  static int _lineOfSelector(String text, String selector) {
    final pattern = RegExp(
      r'(^|[{}\s;/])' + selector.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s*') + r'\s*\{',
      multiLine: true,
    );
    final match = pattern.firstMatch(text);
    if (match == null) return 0;
    final start = match.start + match.group(1)!.length;
    return '\n'.allMatches(text.substring(0, start)).length + 1;
  }

  Future<void> _refreshLayout(DomNode element, int generation) async {
    final layout = _layoutInspector;
    final document = root;
    if (layout == null || document == null) return;
    bool stale() => generation != _styleGeneration || isDisposed;

    Future<FlexContainerInfo?> flexbox({required bool parentsOnly}) async {
      try {
        final response = await session.connection.request(
          layout,
          'getCurrentFlexbox',
          {'node': element.actor, 'onlyLookAtParents': parentsOnly},
          const Duration(seconds: 5),
        );
        final form = response.mapOrNull('flexbox');
        if (form == null) return null;
        final items = await session.connection.request(
          form.str('actor'),
          'getFlexItems',
          const {},
          const Duration(seconds: 5),
        );
        return FlexContainerInfo(
          form.str('containerNodeActorID'),
          form.obj('properties'),
          [
            for (final item in items.maps('flexitems'))
              FlexItemInfo(
                item.str('nodeActorID'),
                item.obj('flexItemSizing'),
                item.obj('properties'),
              ),
          ],
        );
      } on RdpError {
        return null;
      }
    }

    final own = await flexbox(parentsOnly: false);
    if (stale()) return;
    flexContainer = own?.nodeActor == element.actor ? own : null;
    final around = await flexbox(parentsOnly: true);
    if (stale()) return;
    parentFlexContainer = around;
    try {
      final response = await session.connection.request(layout, 'getGrids', {
        'rootNode': document.actor,
      }, const Duration(seconds: 5));
      if (stale()) return;
      grids = [
        for (final grid in response.maps('grids'))
          () {
            final fragment = grid.maps('gridFragments').firstOrNull ?? const {};
            return GridInfo(
              grid.str('containerNodeActorID'),
              fragment.obj('cols').list('tracks').length,
              fragment.obj('rows').list('tracks').length,
            );
          }(),
      ];
    } on RdpError {
      grids = [];
    }
    // Containers the tree has yet to load are looked up for their names.
    for (final grid in grids) {
      if (_nodes[grid.nodeActor] == null) await _loadDeeply(grid.nodeActor);
    }
    changed();
  }

  /// Loads the tree breadth first until the node [actor] is in it.
  Future<void> _loadDeeply(String actor) async {
    var budget = 400;
    final queue = [?root];
    while (queue.isNotEmpty && budget-- > 0) {
      final node = queue.removeAt(0);
      for (final child in await loadChildren(node)) {
        if (child.actor == actor) return;
        if (child.childCount > 0) queue.add(child);
      }
    }
  }

  void setShowBrowserStyles(bool value) {
    session.settings.set('inspector.userAgent', value);
    changed();
    refreshStyles();
  }

  void toggleFlexHighlighter(String nodeActor, bool show, [String color = '#9400FF']) {
    final highlighter = _flexHighlighter;
    if (highlighter == null) return;
    flexHighlighted = show;
    session.connection.notify(highlighter, show ? 'show' : 'hide', {
      if (show) 'node': nodeActor,
      if (show) 'options': {'color': color},
    });
    changed();
  }

  /// The engine's highlighter holds one grid at a time.
  void toggleGridHighlighter(String nodeActor, bool show, [String color = '#9400FF']) {
    final highlighter = _gridHighlighter;
    if (highlighter == null) return;
    highlightedGrids.clear();
    if (show) highlightedGrids.add(nodeActor);
    session.connection.notify(highlighter, show ? 'show' : 'hide', {
      if (show) 'node': nodeActor,
      if (show) 'options': {'color': color},
    });
    changed();
  }

  // ------------------------------------------------------------ editing styles

  DomNode? _ownerOf(AppliedRule rule) => rule.inheritedFrom == null
      ? selectedElement
      : _nodes[rule.inheritedFrom];

  void _record(
    AppliedRule rule,
    String property,
    String? before,
    String? after,
  ) {
    final sheet = rule.styleSheetId == null
        ? null
        : session.styleEditor.sheetById(rule.styleSheetId!);
    final source = rule.isElementStyle
        ? 'Element'
        : sheet?.name ?? 'Style Sheet';
    final selector = rule.isElementStyle
        ? (_ownerOf(rule)?.selectorLabel ?? 'element')
        : rule.selectorText;
    var change = changes
        .where(
          (c) =>
              c.source == source &&
              c.selector == selector &&
              c.property == property,
        )
        .firstOrNull;
    if (change == null) {
      changes.add(change = StyleChange(source, selector, property)
        ..before = before);
    }
    change.after = after;
    if (change.before == change.after) changes.remove(change);
  }

  /// Puts into the page what [rule] should now declare: [set] gives names
  /// their new values, and [remove] takes names out.
  Future<void> _writeRule(
    AppliedRule rule, {
    List<CssDeclaration> set = const [],
    List<String> remove = const [],
  }) async {
    ruleError = '';
    if (rule.isElementStyle) {
      final owner = _ownerOf(rule);
      if (owner == null) return;
      final declarations = <String, CssDeclaration>{
        for (final declaration in rule.declarations)
          if (declaration.enabled) declaration.name: declaration,
      };
      remove.forEach(declarations.remove);
      for (final declaration in set) {
        declarations[declaration.name] = declaration;
      }
      final text = declarations.values.map((d) => d.text).join(' ');
      text.isEmpty
          ? await removeAttribute(owner, 'style')
          : await setAttribute(owner, 'style', text);
    } else {
      try {
        final result = await session.runInPage(
          'const wanted = ${jsonEncode(rule.cssText)};'
          'const selector = ${jsonEncode(rule.selectorText)};'
          'let exact = null, loose = null;'
          'const visit = rules => { for (const rule of rules) {'
          '  if (rule.selectorText !== undefined) {'
          '    if (rule.cssText === wanted) exact = exact || rule;'
          '    else if (rule.selectorText === selector) loose = loose || rule; }'
          '  if (rule.styleSheet) { try { visit(rule.styleSheet.cssRules); } catch (e) {} }'
          '  if (rule.cssRules) visit(rule.cssRules); } };'
          'for (const sheet of document.styleSheets) { try { visit(sheet.cssRules); } catch (e) {} }'
          'const found = exact || loose;'
          'if (!found) throw new Error("This rule is in a style sheet that cannot be edited");'
          'for (const name of ${jsonEncode(remove)}) found.style.removeProperty(name);'
          'const additions = ${jsonEncode([
            for (final d in set) [d.name, d.value, d.important ? 'important' : ''],
          ])};'
          'const refused = [];'
          'for (const [name, value, priority] of additions) { found.style.setProperty(name, value, priority);'
          '  if (!found.style.getPropertyValue(name)) refused.push(name); }'
          'return { text: found.cssText, refused };',
        );
        if (result is Map<String, Object?>) {
          rule.cssText = result.str('text', rule.cssText);
          if (result.strings('refused').isNotEmpty) {
            ruleError =
                'Invalid value for ${result.strings('refused').join(', ')}';
          }
        }
      } catch (error) {
        ruleError = '$error';
      }
    }
    await refreshStyles();
  }

  /// Changes a declaration's name, value or priority. An empty name or value
  /// removes it.
  Future<void> editDeclaration(
    AppliedRule rule,
    CssDeclaration declaration, {
    String? name,
    String? value,
  }) async {
    final nextName = (name ?? declaration.name).trim();
    var nextValue = (value ?? declaration.value).trim();
    var important = declaration.important;
    if (value != null) {
      if (nextValue.endsWith(';')) {
        nextValue = nextValue.substring(0, nextValue.length - 1).trim();
      }
      final priority = RegExp(r'\s*!\s*important$', caseSensitive: false);
      important = priority.hasMatch(nextValue);
      nextValue = nextValue.replaceAll(priority, '');
    }
    if (nextName.isEmpty || nextValue.isEmpty) {
      return removeDeclaration(rule, declaration);
    }
    if (nextName == declaration.name &&
        nextValue == declaration.value &&
        important == declaration.important) {
      return;
    }
    final next = CssDeclaration(
      name: nextName,
      value: nextValue,
      important: important,
      inherits: session.cssProperties[nextName] ?? declaration.inherits,
      isCustomProperty: nextName.startsWith('--'),
      enabled: declaration.enabled,
    );
    if (nextName != declaration.name) {
      _record(rule, declaration.name, declaration.text, null);
      _record(rule, nextName, null, next.text);
    } else {
      _record(rule, nextName, declaration.text, next.text);
    }
    final index = rule.declarations.indexOf(declaration);
    if (index >= 0) rule.declarations[index] = next;
    if (!declaration.enabled) {
      final held = _disabled[rule.identity];
      final at = held?.indexWhere((d) => d.$2 == declaration) ?? -1;
      if (at >= 0) held![at] = (held[at].$1, next);
      changed();
      return;
    }
    await _writeRule(
      rule,
      remove: [if (nextName != declaration.name) declaration.name],
      set: [next],
    );
  }

  Future<void> removeDeclaration(
    AppliedRule rule,
    CssDeclaration declaration,
  ) async {
    _record(rule, declaration.name, declaration.text, null);
    rule.declarations.remove(declaration);
    _disabled[rule.identity]?.removeWhere((d) => d.$2 == declaration);
    if (declaration.enabled) {
      await _writeRule(rule, remove: [declaration.name]);
    } else {
      changed();
    }
  }

  Future<void> addDeclaration(AppliedRule rule, String name, String value) async {
    final trimmed = name.trim();
    var text = value.trim();
    if (trimmed.isEmpty || text.isEmpty) return;
    if (text.endsWith(';')) text = text.substring(0, text.length - 1).trim();
    final priority = RegExp(r'\s*!\s*important$', caseSensitive: false);
    final declaration = CssDeclaration(
      name: trimmed,
      value: text.replaceAll(priority, ''),
      important: priority.hasMatch(text),
      isCustomProperty: trimmed.startsWith('--'),
    );
    rule.declarations.add(declaration);
    _record(rule, trimmed, null, declaration.text);
    await _writeRule(rule, set: [declaration]);
  }

  /// Ticks or unticks a declaration.
  Future<void> setDeclarationEnabled(
    AppliedRule rule,
    CssDeclaration declaration,
    bool enabled,
  ) async {
    if (declaration.enabled == enabled) return;
    final index = rule.declarations.indexOf(declaration);
    declaration.enabled = enabled;
    final held = _disabled.putIfAbsent(rule.identity, () => []);
    if (enabled) {
      held.removeWhere((d) => d.$2 == declaration);
      _record(rule, declaration.name, declaration.text, declaration.text);
      await _writeRule(rule, set: [declaration]);
    } else {
      held.add((index, declaration));
      _record(rule, declaration.name, declaration.text, null);
      await _writeRule(rule, remove: [declaration.name]);
    }
  }

  /// Adds an empty rule for the selected element to a sheet of the tools' own.
  Future<void> addRule() async {
    final element = selectedElement;
    if (element == null || !element.isElement) return;
    var selector = element.tag;
    if (element.id.isNotEmpty) {
      selector = '#${escapeCssIdentifier(element.id)}';
    } else if (element.classes.isNotEmpty) {
      selector = '.${escapeCssIdentifier(element.classes.first)}';
    }
    try {
      await session.runInPage(
        'let node = document.querySelector("style[data-fb-new=rules]");'
        'if (!node) { node = document.createElement("style"); node.setAttribute("data-fb-new", "rules"); document.head.appendChild(node); }'
        'node.sheet.insertRule(${jsonEncode('$selector {}')}, node.sheet.cssRules.length); return true;',
      );
      await refreshStyles();
    } catch (error) {
      ruleError = '$error';
      changed();
    }
  }

  // ------------------------------------------------------------ classes

  /// Classes unticked in the .cls panel, by element, so they can come back.
  final Map<String, Set<String>> removedClasses = {};

  Future<void> setClass(DomNode element, String name, bool on) async {
    final classes = element.classes.toList();
    final removed = removedClasses.putIfAbsent(element.actor, () => {});
    if (on) {
      removed.remove(name);
      if (!classes.contains(name)) classes.add(name);
    } else {
      removed.add(name);
      classes.remove(name);
    }
    await setAttribute(element, 'class', classes.join(' '));
  }

  // ------------------------------------------------------------ pseudo-classes

  Set<String> lockedPseudoClasses(DomNode element) =>
      _lockedPseudoClasses[element.actor] ?? const {};

  /// Styles the element as it would be in a state. The engine cannot force a
  /// state, so each rule for it is copied to match a mark on the element.
  Future<void> setPseudoClassLock(
    DomNode element,
    String pseudoClass,
    bool on,
  ) async {
    final locked = _lockedPseudoClasses.putIfAbsent(element.actor, () => {});
    on ? locked.add(pseudoClass) : locked.remove(pseudoClass);
    changed();
    try {
      await session.runInPage(
        'const element = document.querySelector(${jsonEncode(element.cssSelector)});'
        'if (!element) return false;'
        'const name = ${jsonEncode(pseudoClass)}; const mark = "data-fb-lock-" + name;'
        'let sheet = document.querySelector("style[data-fb-lock=\\"" + name + "\\"]");'
        'if (!$on) { element.removeAttribute(mark); if (!document.querySelector("[" + mark + "]")) sheet?.remove(); return true; }'
        'element.setAttribute(mark, "");'
        'if (sheet) return true;'
        'const pattern = new RegExp(":" + name + "(?![\\\\w-])", "g"); const copies = [];'
        'const visit = rules => { for (const rule of rules) {'
        '  if (rule.selectorText !== undefined) { pattern.lastIndex = 0; if (pattern.test(rule.selectorText))'
        '    copies.push(rule.selectorText.replace(pattern, "[" + mark + "]") + " { " + rule.style.cssText + " }"); }'
        '  else if (rule.cssRules) visit(rule.cssRules); } };'
        'for (const s of document.styleSheets) { try { visit(s.cssRules); } catch (e) {} }'
        'sheet = document.createElement("style"); sheet.setAttribute("data-fb-devtools", ""); sheet.setAttribute("data-fb-lock", name);'
        'sheet.textContent = copies.join("\\n"); document.head.appendChild(sheet); return true;',
      );
    } catch (error) {
      ruleError = '$error';
    }
    await refreshStyles();
  }

  /// The value a custom property has on the selected element.
  String? variableValue(String name) {
    for (final entry in computed) {
      if (entry.key == name) return entry.value;
    }
    for (final rule in rules) {
      for (final declaration in rule.declarations) {
        if (declaration.name == name &&
            declaration.enabled &&
            !declaration.overridden) {
          return declaration.value;
        }
      }
    }
    return null;
  }

  /// A colour as written in a value, following one `var()`.
  Color? colorOf(String value) {
    final match = RegExp(r'^var\(\s*(--[\w-]+)\s*\)$').firstMatch(value.trim());
    if (match != null) {
      final resolved = variableValue(match.group(1)!);
      return resolved == null ? null : parseCssColor(resolved);
    }
    return parseCssColor(value);
  }

  @override
  void dispose() {
    _styleRefresh?.cancel();
    _walkerListener?.call();
    super.dispose();
  }
}
