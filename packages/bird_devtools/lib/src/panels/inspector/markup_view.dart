import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/dom.dart';
import '../../model/session.dart';
import '../../model/inspector_controller.dart';
import '../../ui/code_editor.dart';
import '../../ui/code_view.dart';
import '../../ui/icons.dart';
import '../../ui/inline_editor.dart';
import '../../ui/menu.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../../util/syntax.dart';

const Set<String> _voidElements = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'source', 'track', 'wbr',
};

enum _RowKind { node, close }

class _MarkupRow {
  const _MarkupRow(this.node, this.depth, this.kind);
  final DomNode node;
  final int depth;
  final _RowKind kind;
}

enum _EditKind { tag, attribute, newAttribute, text }

class _Edit {
  const _Edit(this.actor, this.kind, [this.attribute = '']);
  final String actor;
  final _EditKind kind;
  final String attribute;
}

/// The page's document as markup, which can be explored and rewritten.
class MarkupView extends StatefulWidget {
  const MarkupView({super.key, required this.session, this.focusNode});

  final ToolboxSession session;
  final FocusNode? focusNode;

  @override
  State<MarkupView> createState() => _MarkupViewState();
}

class _MarkupViewState extends State<MarkupView> {
  static const double rowHeight = 17;
  static const double indent = 14;

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'markup'));
  List<_MarkupRow> _rows = const [];
  int _revealed = -1;
  _Edit? _editing;

  /// The node whose HTML is being edited, and what is being typed.
  DomNode? _htmlTarget;
  CodeEditingController? _html;

  /// Where a dragged node would go: a row, and whether before it.
  (DomNode, bool)? _drop;

  InspectorController get inspector => widget.session.inspector;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    _ownFocus?.dispose();
    _html?.dispose();
    super.dispose();
  }

  void _buildRows() {
    final rows = <_MarkupRow>[];
    void visit(DomNode node, int depth) {
      if (node.attribute('data-fb-devtools') != null) return;
      rows.add(_MarkupRow(node, depth, _RowKind.node));
      if (inspector.isExpandable(node) && inspector.expanded.contains(node.actor)) {
        for (final child in node.children ?? const <DomNode>[]) {
          visit(child, depth + 1);
        }
        if (node.isElement) rows.add(_MarkupRow(node, depth, _RowKind.close));
      }
    }

    for (final child in inspector.root?.children ?? const <DomNode>[]) {
      visit(child, 0);
    }
    _rows = rows;
  }

  void _reveal() {
    if (_revealed == inspector.revealSerial) return;
    _revealed = inspector.revealSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      final target = inspector.pickerHover ?? inspector.selected;
      final index = _rows.indexWhere((r) => r.node == target && r.kind == _RowKind.node);
      if (index >= 0) _scrollTo(index, center: true);
    });
  }

  void _scrollTo(int index, {bool center = false}) {
    if (!_vertical.hasClients) return;
    final position = _vertical.position;
    final top = index * rowHeight;
    if (top >= position.pixels && top + rowHeight <= position.pixels + position.viewportDimension) {
      return;
    }
    final target = center
        ? top - position.viewportDimension / 2
        : top < position.pixels
        ? top
        : top + rowHeight - position.viewportDimension;
    _vertical.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  // ------------------------------------------------------------ keys

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_editing != null || _htmlTarget != null || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final selected = inspector.selected;
    if (selected == null) return KeyEventResult.ignored;
    final nodes = [for (final row in _rows) if (row.kind == _RowKind.node) row.node];
    final index = nodes.indexOf(selected);
    void go(int to) {
      if (to < 0 || to >= nodes.length) return;
      inspector.select(nodes[to]);
      final row = _rows.indexWhere((r) => r.node == nodes[to]);
      if (row >= 0) _scrollTo(row);
    }

    final key = event.logicalKey;
    final command = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
    if (command && key == LogicalKeyboardKey.keyC) {
      inspector.html(selected).then(inspector.copy);
    } else if (command) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      go(index + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      go(index - 1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (inspector.expanded.contains(selected.actor) && inspector.isExpandable(selected)) {
        inspector.collapse(selected);
      } else if (selected.parent case final parent? when !parent.isDocument) {
        go(nodes.indexOf(parent));
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (!inspector.isExpandable(selected)) return KeyEventResult.handled;
      if (inspector.expanded.contains(selected.actor)) {
        go(index + 1);
      } else {
        inspector.expand(selected);
      }
    } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      inspector.removeNode(selected);
    } else if (key == LogicalKeyboardKey.f2) {
      _editHtml(selected);
    } else if (key == LogicalKeyboardKey.enter) {
      if (selected.isElement) {
        setState(() {
          _editing = selected.attributes.isEmpty
              ? _Edit(selected.actor, _EditKind.newAttribute)
              : _Edit(selected.actor, _EditKind.attribute, selected.attributes.first.name);
        });
      } else if (selected.isText || selected.isComment) {
        setState(() => _editing = _Edit(selected.actor, _EditKind.text));
      }
    } else if (key == LogicalKeyboardKey.keyH) {
      _toggleHidden(selected);
    } else if (key == LogicalKeyboardKey.keyS) {
      inspector.scrollIntoView(selected);
    } else if (key == LogicalKeyboardKey.escape && inspector.picking) {
      inspector.stopPicker();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  final Set<String> _hidden = {};

  void _toggleHidden(DomNode node) {
    if (!node.isElement) return;
    final style = node.attribute('style') ?? '';
    const mark = 'visibility: hidden !important;';
    if (_hidden.remove(node.actor) || style.contains(mark)) {
      final next = style.replaceAll(mark, '').trim();
      next.isEmpty ? inspector.removeAttribute(node, 'style') : inspector.setAttribute(node, 'style', next);
    } else {
      _hidden.add(node.actor);
      inspector.setAttribute(node, 'style', '${style.isEmpty ? '' : '${style.trimRight().replaceAll(RegExp(r';$'), '')}; '}$mark');
    }
  }

  // ------------------------------------------------------------ editing HTML

  Future<void> _editHtml(DomNode node) async {
    final html = await inspector.html(node);
    if (!mounted || html.isEmpty) return;
    setState(() {
      _html?.dispose();
      _html = CodeEditingController(text: html, language: SyntaxLanguage.html);
      _htmlTarget = node;
    });
  }

  void _finishHtml(bool save) {
    final node = _htmlTarget;
    final text = _html?.text;
    setState(() => _htmlTarget = null);
    _focus.requestFocus();
    if (save && node != null && text != null) inspector.setOuterHtml(node, text);
  }

  Future<void> _paste(DomNode node, String where) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (where == 'outer') return inspector.setOuterHtml(node, text);
    final html = await inspector.html(node, inner: where != 'before' && where != 'after');
    if (where == 'before' || where == 'after') {
      return inspector.setOuterHtml(node, where == 'before' ? '$text$html' : '$html$text');
    }
    final outer = await inspector.html(node);
    final open = outer.indexOf('>') + 1;
    final close = outer.lastIndexOf('</');
    if (open <= 0 || close < open) return;
    final inner = switch (where) {
      'inner' => text,
      'firstChild' => '$text$html',
      _ => '$html$text',
    };
    await inspector.setOuterHtml(node, '${outer.substring(0, open)}$inner${outer.substring(close)}');
  }

  // ------------------------------------------------------------ menu

  List<DtMenuEntry> _menu(DomNode node, String? attribute) {
    final element = node.isElement;
    final modifiable = inspector.canModify(node);
    return [
      DtMenuItem('Edit As HTML', shortcut: 'F2', enabled: element, onSelected: () => _editHtml(node)),
      DtMenuItem('Create New Node', enabled: element && !_voidElements.contains(node.tag), onSelected: () => inspector.addChild(node)),
      DtMenuItem('Duplicate Node', enabled: element && modifiable, onSelected: () => inspector.duplicateNode(node)),
      DtMenuItem('Delete Node', shortcut: '⌫', enabled: modifiable, onSelected: () => inspector.removeNode(node)),
      const DtMenuItem.separator(),
      DtMenuItem(
        'Attributes',
        enabled: element,
        submenu: [
          DtMenuItem('Add Attribute', onSelected: () => setState(() => _editing = _Edit(node.actor, _EditKind.newAttribute))),
          DtMenuItem(
            'Copy Attribute Value',
            enabled: attribute != null,
            onSelected: () => inspector.copy(node.attribute(attribute!) ?? ''),
          ),
          DtMenuItem(
            'Edit Attribute${attribute == null ? '' : ' “$attribute”'}',
            enabled: attribute != null,
            onSelected: () => setState(() => _editing = _Edit(node.actor, _EditKind.attribute, attribute!)),
          ),
          DtMenuItem(
            'Remove Attribute${attribute == null ? '' : ' “$attribute”'}',
            enabled: attribute != null,
            onSelected: () => inspector.removeAttribute(node, attribute!),
          ),
        ],
      ),
      const DtMenuItem.separator(),
      DtMenuItem(
        'Change Pseudo-class',
        enabled: element,
        submenu: [
          for (final name in forcePseudoClasses)
            DtMenuItem(
              ':$name',
              checked: inspector.lockedPseudoClasses(node).contains(name),
              onSelected: () => inspector.setPseudoClassLock(node, name, !inspector.lockedPseudoClasses(node).contains(name)),
            ),
        ],
      ),
      DtMenuItem(
        'Use in Console',
        enabled: element,
        onSelected: () {
          inspector.select(node);
          widget.session.console.draft = r'$0';
          widget.session.selectTool('console');
        },
      ),
      const DtMenuItem.separator(),
      DtMenuItem(
        'Copy',
        submenu: [
          DtMenuItem('Inner HTML', enabled: element, onSelected: () => inspector.html(node, inner: true).then(inspector.copy)),
          DtMenuItem('Outer HTML', shortcut: '⌘C', onSelected: () => inspector.html(node).then(inspector.copy)),
          DtMenuItem('CSS Selector', enabled: element, onSelected: () => inspector.copy(node.cssSelector)),
          DtMenuItem('CSS Path', enabled: element, onSelected: () => inspector.copy(node.cssPath)),
          DtMenuItem('XPath', onSelected: () => inspector.copy(node.xpath)),
        ],
      ),
      DtMenuItem(
        'Paste',
        submenu: [
          DtMenuItem('Inner HTML', enabled: element, onSelected: () => _paste(node, 'inner')),
          DtMenuItem('Outer HTML', enabled: element && modifiable, onSelected: () => _paste(node, 'outer')),
          DtMenuItem('Before', enabled: element && modifiable, onSelected: () => _paste(node, 'before')),
          DtMenuItem('After', enabled: element && modifiable, onSelected: () => _paste(node, 'after')),
          DtMenuItem('As First Child', enabled: element, onSelected: () => _paste(node, 'firstChild')),
          DtMenuItem('As Last Child', enabled: element, onSelected: () => _paste(node, 'lastChild')),
        ],
      ),
      const DtMenuItem.separator(),
      DtMenuItem('Expand All', enabled: node.childCount > 0, onSelected: () => inspector.expandAll(node)),
      DtMenuItem('Collapse', enabled: inspector.expanded.contains(node.actor), onSelected: () => inspector.collapse(node)),
      DtMenuItem('Scroll Into View', shortcut: 'S', enabled: element, onSelected: () => inspector.scrollIntoView(node)),
      DtMenuItem('Show/Hide Element', shortcut: 'H', enabled: element, onSelected: () => _toggleHidden(node)),
    ];
  }

  // ------------------------------------------------------------ building

  int _length(_MarkupRow row) {
    final node = row.node;
    var length = row.depth * 2 + node.nodeName.length * 2 + 6;
    for (final attribute in node.attributes) {
      length += attribute.name.length + attribute.value.length.clamp(0, 120) + 4;
    }
    length += (node.nodeValue?.length ?? 0).clamp(0, 400);
    length += node.inlineText?.nodeValue?.length ?? 0;
    return length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return ListenableBuilder(
      listenable: inspector,
      builder: (context, _) {
        _buildRows();
        _reveal();
        if (inspector.root == null) {
          return const DtEmptyState('Waiting for the page…');
        }
        final style = context.monoStyle();
        final characterWidth = monoCharacterWidth(style);
        var longest = 0;
        for (final row in _rows) {
          final length = _length(row);
          if (length > longest) longest = length;
        }
        return ColoredBox(
          color: colors.body,
          child: Column(
            children: [
              Expanded(
                child: Focus(
                  focusNode: _focus,
                  onKeyEvent: _onKey,
                  child: MouseRegion(
                    onExit: (_) => inspector.unhighlight(),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Scrollbar2D(
                        horizontal: _horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: (longest * characterWidth + 48).clamp(constraints.maxWidth, 12000),
                            height: constraints.maxHeight,
                            child: ListView.builder(
                              controller: _vertical,
                              itemExtent: rowHeight,
                              padding: const EdgeInsets.only(top: 2, bottom: 16),
                              itemCount: _rows.length,
                              itemBuilder: (context, index) => _row(context, _rows[index]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_htmlTarget != null) _htmlEditor(context),
            ],
          ),
        );
      },
    );
  }

  Widget _htmlEditor(BuildContext context) => SizedBox(
    height: 200,
    child: DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.dt.accent, width: 2))),
      child: Column(
        children: [
          DtToolbar(
            height: 28,
            children: [
              Text('Edit As HTML — <${_htmlTarget!.selectorLabel}>', style: context.uiStyle(color: context.dt.textStrong)),
              const Spacer(),
              DtButton('Cancel', onPressed: () => _finishHtml(false)),
              const SizedBox(width: 6),
              DtButton('Save ⌘⏎', primary: true, onPressed: () => _finishHtml(true)),
            ],
          ),
          Expanded(
            child: DtCodeEditor(
              controller: _html!,
              autofocus: true,
              onKey: (event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _finishHtml(false);
                  return KeyEventResult.handled;
                }
                final command = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
                if (command && event.logicalKey == LogicalKeyboardKey.enter) {
                  _finishHtml(true);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _row(BuildContext context, _MarkupRow row) {
    final colors = context.dt;
    final node = row.node;
    final close = row.kind == _RowKind.close;
    final selected = inspector.selected == node && !close;
    final hovering = inspector.pickerHover == node;
    final drop = _drop?.$1 == node && !close;

    Widget content(bool hovered) {
      final background = selected
          ? colors.selection
          : hovering || hovered
          ? colors.rowHover
          : inspector.flashing.contains(node.actor) && !close
          ? colors.flash
          : null;
      return Container(
        height: rowHeight,
        decoration: BoxDecoration(
          color: background,
          border: drop ? Border(top: _drop!.$2 ? BorderSide(color: colors.accent, width: 2) : BorderSide.none, bottom: !_drop!.$2 ? BorderSide(color: colors.accent, width: 2) : BorderSide.none) : null,
        ),
        padding: EdgeInsets.only(left: 4 + row.depth * indent),
        child: Row(
          children: [
            SizedBox(
              width: 13,
              child: !close && inspector.isExpandable(node)
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (HardwareKeyboard.instance.isAltPressed) {
                          inspector.expandAll(node);
                        } else if (inspector.expanded.contains(node.actor)) {
                          inspector.collapse(node);
                        } else {
                          inspector.expand(node);
                        }
                      },
                      child: Center(
                        child: DtIcon(
                          inspector.expanded.contains(node.actor) ? DtGlyph.twistyDown : DtGlyph.twistyRight,
                          size: 8,
                          color: selected ? colors.selectionText : colors.textDim,
                        ),
                      ),
                    )
                  : null,
            ),
            ..._markup(context, node, close: close, selected: selected),
          ],
        ),
      );
    }

    final tile = DtHover(
      onEnter: () => inspector.highlight(node),
      builder: (context, hovered) => Listener(
        onPointerDown: (event) {
          if (_editing != null) return;
          _focus.requestFocus();
          if (event.buttons == kPrimaryButton || event.buttons == kSecondaryButton) {
            inspector.select(node);
          }
        },
        child: content(hovered),
      ),
      onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, _menu(node, _menuAttribute)),
      onDoubleTap: close || !inspector.isExpandable(node)
          ? null
          : () => inspector.expanded.contains(node.actor) ? inspector.collapse(node) : inspector.expand(node),
    );

    if (close || !inspector.canModify(node) || _editing != null) return _dropTarget(node, tile);
    return _dropTarget(
      node,
      Draggable<DomNode>(
        data: node,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: DtTheme(
          colors: colors,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: colors.popup.withValues(alpha: 0.92),
            child: Text('<${node.isElement ? node.selectorLabel : node.nodeName}>', style: context.monoStyle(color: colors.tag)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: tile),
        child: tile,
      ),
    );
  }

  Widget _dropTarget(DomNode node, Widget child) => DragTarget<DomNode>(
    onWillAcceptWithDetails: (details) {
      for (DomNode? p = node; p != null; p = p.parent) {
        if (p == details.data) return false;
      }
      return node.parent != null && !node.isPseudoElement;
    },
    onMove: (details) {
      final box = context.findRenderObject();
      if (box is! RenderBox) return;
      final local = box.globalToLocal(details.offset);
      final scrolled = local.dy + (_vertical.hasClients ? _vertical.offset : 0) - 2;
      final before = scrolled % rowHeight < rowHeight / 2;
      if (_drop?.$1 != node || _drop?.$2 != before) setState(() => _drop = (node, before));
    },
    onLeave: (_) => setState(() => _drop = null),
    onAcceptWithDetails: (details) {
      final drop = _drop;
      setState(() => _drop = null);
      if (drop == null) return;
      final (target, before) = drop;
      if (!before && target.isElement && inspector.expanded.contains(target.actor)) {
        inspector.moveNode(details.data, target, target.children?.firstOrNull);
        return;
      }
      final parent = target.parent;
      if (parent == null || parent.isDocument) return;
      final siblings = parent.children ?? const <DomNode>[];
      final index = siblings.indexOf(target) + (before ? 0 : 1);
      inspector.moveNode(details.data, parent, index < siblings.length ? siblings[index] : null);
    },
    builder: (context, candidates, rejected) => child,
  );

  /// The attribute the pointer was on when a menu was asked for.
  String? _menuAttribute;

  List<Widget> _markup(BuildContext context, DomNode node, {required bool close, required bool selected}) {
    final colors = context.dt;
    Color pick(Color color) => selected ? colors.selectionText : color;
    final dim = !node.isDisplayed && node.isElement && !const {'head', 'meta', 'title', 'style', 'script', 'link'}.contains(node.tag);
    TextStyle style(Color color) => context.monoStyle(color: pick(dim && !selected ? color.withValues(alpha: 0.55) : color));
    Widget text(String value, Color color) => Text(value, style: style(color), maxLines: 1, softWrap: false);

    final editing = _editing?.actor == node.actor && !close ? _editing : null;

    if (node.nodeType == DomNode.doctypeNode) {
      return [text('<!DOCTYPE ${node.nodeName}>', colors.textDim)];
    }
    if (node.isPseudoElement) return [text(node.tag, colors.tag)];
    if (node.isShadowRoot) return [text('#shadow-root', colors.textDim)];
    if (node.isText || node.isComment) {
      final value = node.nodeValue ?? '';
      if (editing?.kind == _EditKind.text) {
        return [
          DtInlineEditor(
            initial: value,
            style: context.monoStyle(color: colors.textStrong),
            maxWidth: 600,
            onCancel: _endEdit,
            onCommit: (next, end) {
              _endEdit();
              if (next != value) inspector.setTextContent(node, next);
            },
          ),
        ];
      }
      var shown = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (shown.length > 400) shown = '${shown.substring(0, 400)}…';
      return [
        GestureDetector(
          onDoubleTap: () => setState(() => _editing = _Edit(node.actor, _EditKind.text)),
          child: node.isComment ? text('<!--${value.length > 400 ? shown : value.replaceAll('\n', '↵')}-->', colors.comment) : text(shown, colors.textStrong),
        ),
      ];
    }
    if (!node.isElement) return [text(node.nodeName, colors.textDim)];

    final tag = node.tag;
    if (close) return [text('</', colors.tag), text(tag, colors.tag), text('>', colors.tag)];

    final widgets = <Widget>[text('<', colors.tag)];
    if (editing?.kind == _EditKind.tag) {
      widgets.add(
        DtInlineEditor(
          initial: tag,
          onCancel: _endEdit,
          onCommit: (next, end) {
            _endEdit();
            if (next.trim().isNotEmpty && next.trim() != tag) inspector.setTagName(node, next.trim());
          },
        ),
      );
    } else {
      widgets.add(
        _Editable(
          onDoubleTap: inspector.canModify(node) ? () => setState(() => _editing = _Edit(node.actor, _EditKind.tag)) : null,
          child: text(tag, colors.tag),
        ),
      );
    }
    final attributes = node.attributes.where((a) => !a.name.startsWith('data-fb-')).toList();
    for (final (index, attribute) in attributes.indexed) {
      widgets.add(text(' ', colors.text));
      final whole = '${attribute.name}="${attribute.value.replaceAll('"', '&quot;')}"';
      if (editing?.kind == _EditKind.attribute && editing!.attribute == attribute.name) {
        widgets.add(
          DtInlineEditor(
            initial: whole,
            onCancel: _endEdit,
            onCommit: (next, end) {
              final following = index + 1 < attributes.length ? attributes[index + 1].name : null;
              setState(() {
                _editing = switch (end) {
                  EditEnd.tab => following == null ? _Edit(node.actor, _EditKind.newAttribute) : _Edit(node.actor, _EditKind.attribute, following),
                  EditEnd.backTab => index > 0 ? _Edit(node.actor, _EditKind.attribute, attributes[index - 1].name) : null,
                  _ => null,
                };
              });
              if (_editing == null) _focus.requestFocus();
              if (next != whole) inspector.replaceAttribute(node, attribute.name, next);
            },
          ),
        );
        continue;
      }
      var value = attribute.value.replaceAll('\n', '↵');
      if (value.length > 120) value = '${value.substring(0, 60)}…${value.substring(value.length - 56)}';
      final isLink = const {'href', 'src'}.contains(attribute.name);
      widgets.add(
        Listener(
          onPointerDown: (event) => _menuAttribute = attribute.name,
          child: _Editable(
            onDoubleTap: () => setState(() => _editing = _Edit(node.actor, _EditKind.attribute, attribute.name)),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: attribute.name, style: TextStyle(color: pick(colors.attributeName))),
                  TextSpan(text: '="', style: TextStyle(color: pick(colors.tag))),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      color: pick(colors.attributeValue),
                      decoration: isLink ? TextDecoration.underline : null,
                      decorationColor: pick(colors.attributeValue),
                    ),
                    recognizer: null,
                  ),
                  TextSpan(text: '"', style: TextStyle(color: pick(colors.tag))),
                ],
              ),
              style: style(colors.text),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      );
    }
    if (editing?.kind == _EditKind.newAttribute) {
      widgets
        ..add(text(' ', colors.text))
        ..add(
          DtInlineEditor(
            initial: '',
            minWidth: 70,
            placeholder: 'name="value"',
            onCancel: _endEdit,
            onCommit: (next, end) {
              _endEdit();
              if (next.trim().isNotEmpty) inspector.addAttributes(node, next);
            },
          ),
        );
    }
    widgets.add(
      GestureDetector(
        onDoubleTap: () => setState(() => _editing = _Edit(node.actor, _EditKind.newAttribute)),
        child: text('>', colors.tag),
      ),
    );

    final open = inspector.expanded.contains(node.actor) && inspector.isExpandable(node);
    final inline = node.inlineText;
    if (inline != null) {
      widgets
        ..add(
          _editing?.actor == inline.actor
              ? DtInlineEditor(
                  initial: inline.nodeValue ?? '',
                  onCancel: _endEdit,
                  onCommit: (next, end) {
                    _endEdit();
                    if (next != inline.nodeValue) inspector.setTextContent(inline, next);
                  },
                )
              : _Editable(
                  onDoubleTap: () => setState(() => _editing = _Edit(inline.actor, _EditKind.text)),
                  child: text(inline.nodeValue ?? '', colors.textStrong),
                ),
        )
        ..add(text('</$tag>', colors.tag));
    } else if (!open && !_voidElements.contains(tag)) {
      if (node.childCount > 0) {
        widgets.add(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => inspector.expand(node),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              height: 11,
              decoration: BoxDecoration(
                color: selected ? const Color(0x40FFFFFF) : colors.toolbarHover,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text('…', style: style(colors.textDim).copyWith(height: 0.8)),
            ),
          ),
        );
      }
      widgets.add(text('</$tag>', colors.tag));
    }

    // Firefox's badges for what lays out its children.
    final display = node.displayType;
    if (display == 'flex' || display == 'inline-flex') {
      widgets.add(
        _Badge(
          'flex',
          active: inspector.flexHighlighted && inspector.flexContainer?.nodeActor == node.actor,
          onTap: () => inspector.toggleFlexHighlighter(node.actor, !inspector.flexHighlighted),
        ),
      );
    } else if (display == 'grid' || display == 'inline-grid') {
      widgets.add(
        _Badge(
          'grid',
          active: inspector.highlightedGrids.contains(node.actor),
          onTap: () => inspector.toggleGridHighlighter(node.actor, !inspector.highlightedGrids.contains(node.actor)),
        ),
      );
    }
    if (node.isScrollable) widgets.add(const _Badge('scroll'));
    return widgets;
  }

  void _endEdit() {
    setState(() => _editing = null);
    _focus.requestFocus();
  }
}

/// Text in the markup that a double click turns into a field.
class _Editable extends StatelessWidget {
  const _Editable({required this.child, required this.onDoubleTap});
  final Widget child;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) => _DoubleClick(onDoubleClick: onDoubleTap, child: child);
}

/// Hears a double click without holding up the single ones around it.
class _DoubleClick extends StatefulWidget {
  const _DoubleClick({required this.onDoubleClick, required this.child});
  final VoidCallback? onDoubleClick;
  final Widget child;

  @override
  State<_DoubleClick> createState() => _DoubleClickState();
}

class _DoubleClickState extends State<_DoubleClick> {
  Duration _last = Duration.zero;
  Offset _at = Offset.zero;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons != kPrimaryButton) return;
      final double = event.timeStamp - _last < kDoubleTapTimeout && (event.position - _at).distance < kDoubleTapSlop;
      _last = double ? Duration.zero : event.timeStamp;
      _at = event.position;
      if (double) widget.onDoubleClick?.call();
    },
    child: widget.child,
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.onTap, this.active = false});
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            height: 13,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF9400FF) : colors.toolbar,
              border: Border.all(color: active ? const Color(0xFF9400FF) : colors.splitterStrong),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(label, style: context.uiStyle(size: 9, color: active ? const Color(0xFFFFFFFF) : colors.textDim).copyWith(height: 1)),
          ),
        ),
      ),
    );
  }
}
