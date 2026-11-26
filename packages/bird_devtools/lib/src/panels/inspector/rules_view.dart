import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/dom.dart';
import '../../model/inspector_controller.dart';
import '../../model/session.dart';
import '../../model/styles.dart';
import '../../ui/color_picker.dart';
import '../../ui/icons.dart';
import '../../ui/inline_editor.dart';
import '../../ui/menu.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../../util/css_color.dart';
import '../../util/css_values.dart';

enum _Field { name, value }

/// What is being edited: a declaration's name or value, or, with no
/// declaration, one being added to the rule.
class _Editing {
  const _Editing(this.rule, this.declaration, this.field, [this.newName = '']);
  final String rule;
  final int declaration;
  final _Field field;
  final String newName;
}

/// The Rules view: the declarations that apply to the selected element, in
/// order of precedence, editable in place.
class RulesView extends StatefulWidget {
  const RulesView({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<RulesView> createState() => _RulesViewState();
}

class _RulesViewState extends State<RulesView> {
  _Editing? _editing;
  String _filter = '';
  bool _showPseudoPanel = false;
  bool _showClassPanel = false;
  bool _pseudoElementsOpen = true;
  final TextEditingController _newClass = TextEditingController();

  InspectorController get inspector => widget.session.inspector;

  @override
  void dispose() {
    _newClass.dispose();
    super.dispose();
  }

  /// Rules are rebuilt as the page changes, so they are told apart by what
  /// stays the same about them.
  String _key(AppliedRule rule) => '${rule.identity}|${inspector.rules.indexOf(rule)}';

  void _edit(_Editing? next) {
    if (mounted) setState(() => _editing = next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: inspector,
    builder: (context, _) => ColoredBox(
      color: context.dt.sidebar,
      child: Column(
        children: [
          _toolbar(context),
          if (_showPseudoPanel) _pseudoPanel(context),
          if (_showClassPanel) _classPanel(context),
          if (inspector.ruleError.isNotEmpty)
            Container(
              width: double.infinity,
              color: context.dt.errorBackground,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(inspector.ruleError, style: context.uiStyle(color: context.dt.errorText, size: 11)),
            ),
          Expanded(child: _rules(context)),
        ],
      ),
    ),
  );

  Widget _toolbar(BuildContext context) {
    final element = inspector.selectedElement;
    return DtToolbar(
      height: 25,
      children: [
        Expanded(
          child: DtSearchBox(
            value: _filter,
            placeholder: 'Filter Styles',
            height: 19,
            onChanged: (value) => setState(() => _filter = value),
          ),
        ),
        const SizedBox(width: 3),
        _TextToggle(
          ':hov',
          tooltip: 'Toggle pseudo-classes',
          active: _showPseudoPanel,
          onTap: () => setState(() {
            _showPseudoPanel = !_showPseudoPanel;
            _showClassPanel = false;
          }),
        ),
        _TextToggle(
          '.cls',
          tooltip: 'Toggle classes',
          active: _showClassPanel,
          onTap: () => setState(() {
            _showClassPanel = !_showClassPanel;
            _showPseudoPanel = false;
          }),
        ),
        DtIconButton(
          DtGlyph.plus,
          width: 22,
          iconSize: 12,
          tooltip: 'Add new rule',
          onPressed: element == null ? null : inspector.addRule,
        ),
        DtIconButton(
          DtGlyph.gear,
          width: 22,
          iconSize: 12,
          tooltip: 'Style options',
          onPressed: () => showDtMenu(context, _menuAnchor(context), [
            DtMenuItem(
              'Show Browser Styles',
              checked: inspector.showBrowserStyles,
              onSelected: () => inspector.setShowBrowserStyles(!inspector.showBrowserStyles),
            ),
          ]),
        ),
      ],
    );
  }

  Offset _menuAnchor(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return Offset.zero;
    return box.localToGlobal(Offset(box.size.width - 8, 25));
  }

  Widget _pseudoPanel(BuildContext context) {
    final element = inspector.selectedElement;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: context.dt.sidebar,
        border: Border(bottom: BorderSide(color: context.dt.splitter)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 5,
        children: [
          for (final name in forcePseudoClasses)
            SizedBox(
              width: 104,
              child: DtCheckbox(
                label: ':$name',
                value: element != null && inspector.lockedPseudoClasses(element).contains(name),
                onChanged: element == null ? null : (on) => inspector.setPseudoClassLock(element, name, on),
              ),
            ),
        ],
      ),
    );
  }

  Widget _classPanel(BuildContext context) {
    final colors = context.dt;
    final element = inspector.selectedElement;
    final present = element?.classes ?? const <String>[];
    final removed = element == null ? const <String>{} : inspector.removedClasses[element.actor] ?? const <String>{};
    final all = [...present, ...removed.where((name) => !present.contains(name))];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.splitter))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(color: colors.inputBackground, border: Border.all(color: colors.inputBorder)),
            child: DtTextInput(
              controller: _newClass,
              placeholder: 'Add new class',
              onSubmitted: (value) {
                final name = value.trim();
                if (element == null || name.isEmpty) return;
                _newClass.clear();
                inspector.setClass(element, name, true);
              },
            ),
          ),
          const SizedBox(height: 5),
          if (all.isEmpty)
            Text('No classes on this element', style: context.uiStyle(color: colors.textDim, size: 11))
          else
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final name in all)
                  DtCheckbox(
                    label: name,
                    value: present.contains(name),
                    onChanged: (on) => inspector.setClass(element!, name, on),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  bool _matchesFilter(AppliedRule rule) {
    if (_filter.isEmpty) return true;
    final needle = _filter.toLowerCase();
    return rule.selectorText.toLowerCase().contains(needle) ||
        rule.declarations.any((d) => '${d.name}: ${d.value}'.toLowerCase().contains(needle));
  }

  static final RegExp _pseudoElement = RegExp(r'::(before|after|marker|placeholder|selection|first-line|first-letter|backdrop)\b|:(before|after)\b');

  bool _isPseudoElementRule(AppliedRule rule) =>
      rule.inheritedFrom == null &&
      inspector.selectedElement?.isPseudoElement != true &&
      rule.matchedSelectors.isNotEmpty &&
      rule.matchedSelectors.every((i) => i < rule.selectors.length && _pseudoElement.hasMatch(rule.selectors[i]));

  Widget _rules(BuildContext context) {
    final colors = context.dt;
    if (inspector.selectedElement == null) {
      return const DtEmptyState('No element selected.');
    }
    final rules = inspector.rules.where(_matchesFilter).toList();
    final pseudo = rules.where(_isPseudoElementRule).toList();
    final children = <Widget>[];
    if (pseudo.isNotEmpty) {
      children.add(
        DtAccordion(
          title: 'Pseudo-elements',
          expanded: _pseudoElementsOpen,
          onToggle: () => setState(() => _pseudoElementsOpen = !_pseudoElementsOpen),
          child: Column(children: [for (final rule in pseudo) _rule(context, rule)]),
        ),
      );
      children.add(_header(context, 'This Element'));
    }
    String? inheritedFrom;
    for (final rule in rules) {
      if (pseudo.contains(rule)) continue;
      if (rule.inheritedFrom != null && rule.inheritedFrom != inheritedFrom) {
        inheritedFrom = rule.inheritedFrom;
        final from = inspector.nodeFor(inheritedFrom!);
        children.add(_header(context, 'Inherited from', node: from));
      }
      children.add(_rule(context, rule));
    }
    if (children.isEmpty) {
      return DtEmptyState(inspector.rulesLoading ? 'Loading…' : 'No matching rules.');
    }
    return DefaultTextStyle(
      style: context.monoStyle(color: colors.textStrong),
      child: ListView(children: children),
    );
  }

  Widget _header(BuildContext context, String text, {DomNode? node}) {
    final colors = context.dt;
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.splitter)),
      ),
      child: Row(
        children: [
          Text(text, style: context.uiStyle(color: colors.textDim, size: 11)),
          if (node != null) ...[
            const SizedBox(width: 4),
            DtHover(
              cursor: SystemMouseCursors.click,
              onEnter: () => inspector.highlight(node),
              onExit: inspector.unhighlight,
              onTap: () => inspector.select(node, reveal: true),
              builder: (context, hovered) => Text(
                node.selectorLabel,
                style: context.monoStyle(color: colors.accent, decoration: hovered ? TextDecoration.underline : null),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ one rule

  Widget _rule(BuildContext context, AppliedRule rule) {
    final colors = context.dt;
    final key = _key(rule);
    final editingHere = _editing?.rule == key;
    final editable = !rule.isSystem;
    final adding = editingHere && _editing!.declaration < 0;
    final sheet = rule.styleSheetId == null ? null : widget.session.styleEditor.sheetById(rule.styleSheetId!);

    void startAdding() {
      if (editable && _editing == null) _edit(_Editing(key, -1, _Field.name));
    }

    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.splitter))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final ancestor in rule.ancestors)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(ancestor, style: context.monoStyle(color: colors.textDim)),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: startAdding,
            onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, _ruleMenu(rule, null, startAdding)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 16),
                Expanded(child: _selector(context, rule)),
                const SizedBox(width: 8),
                if (!rule.isElementStyle)
                  DtHover(
                    cursor: sheet == null ? MouseCursor.defer : SystemMouseCursors.click,
                    onTap: sheet == null
                        ? null
                        : () {
                            widget.session.styleEditor.reveal(sheet, rule.sourceLine);
                            widget.session.selectTool('styleeditor');
                          },
                    builder: (context, hovered) => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        rule.isSystem
                            ? 'user agent'
                            : sheet == null
                            ? 'style sheet'
                            : '${sheet.href.isEmpty ? 'inline' : sheet.name}${rule.sourceLine > 0 ? ':${rule.sourceLine}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.monoStyle(
                          color: hovered && sheet != null ? colors.accent : colors.textDim,
                          decoration: hovered && sheet != null ? TextDecoration.underline : null,
                        ),
                      ),
                    ),
                  )
                else
                  Text('inline', style: context.monoStyle(color: colors.textDim)),
              ],
            ),
          ),
          for (final (index, declaration) in rule.declarations.indexed)
            if (declarationReaches(rule, declaration))
              _declaration(context, rule, key, index, declaration, editable, startAdding),
          if (adding) _newDeclaration(context, rule, key),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: startAdding,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text('}', style: context.monoStyle(color: colors.textStrong)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selector(BuildContext context, AppliedRule rule) {
    final colors = context.dt;
    if (rule.isElementStyle) {
      return Text('element {', style: context.monoStyle(color: colors.textStrong));
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final (index, selector) in rule.selectors.indexed) ...[
            if (index > 0) TextSpan(text: ', ', style: TextStyle(color: colors.textDim)),
            TextSpan(
              text: selector,
              style: TextStyle(
                color: rule.matchedSelectors.isEmpty || rule.matchedSelectors.contains(index)
                    ? colors.textStrong
                    : colors.textDim,
              ),
            ),
          ],
          const TextSpan(text: ' {'),
        ],
      ),
      style: context.monoStyle(color: colors.textStrong),
    );
  }

  List<DtMenuEntry> _ruleMenu(AppliedRule rule, CssDeclaration? declaration, VoidCallback add) {
    String ruleText() {
      final body = rule.declarations.where((d) => d.enabled).map((d) => '  ${d.text}').join('\n');
      return '${rule.selectorText} {\n$body\n}';
    }

    void copy(String text) => Clipboard.setData(ClipboardData(text: text));
    return [
      if (declaration != null) ...[
        DtMenuItem('Copy Declaration', onSelected: () => copy(declaration.text)),
        DtMenuItem('Copy Property Name', onSelected: () => copy(declaration.name)),
        DtMenuItem('Copy Property Value', onSelected: () => copy(declaration.value)),
        const DtMenuItem.separator(),
      ],
      DtMenuItem('Copy Rule', onSelected: () => copy(ruleText())),
      DtMenuItem('Copy Selector', enabled: !rule.isElementStyle, onSelected: () => copy(rule.selectorText)),
      DtMenuItem(
        'Copy All Declarations',
        onSelected: () => copy(rule.declarations.where((d) => d.enabled).map((d) => d.text).join('\n')),
      ),
      const DtMenuItem.separator(),
      DtMenuItem('Add New Declaration', enabled: !rule.isSystem, onSelected: add),
      DtMenuItem('Add New Rule', onSelected: inspector.addRule),
      if (declaration != null)
        DtMenuItem('Delete Declaration', enabled: !rule.isSystem, onSelected: () => inspector.removeDeclaration(rule, declaration)),
    ];
  }

  Widget _declaration(
    BuildContext context,
    AppliedRule rule,
    String key,
    int index,
    CssDeclaration declaration,
    bool editable,
    VoidCallback add,
  ) {
    final editing = _editing?.rule == key && _editing!.declaration == index ? _editing!.field : null;
    final colors = context.dt;
    final invalid = !declaration.isValid || !declaration.isNameValid;
    final struck = declaration.overridden || !declaration.enabled || invalid;

    void next(EditEnd end, _Field from) {
      switch (end) {
        case EditEnd.tab:
          if (from == _Field.name) {
            _edit(_Editing(key, index, _Field.value));
          } else if (index + 1 < rule.declarations.length) {
            _edit(_Editing(key, index + 1, _Field.name));
          } else {
            _edit(_Editing(key, -1, _Field.name));
          }
        case EditEnd.backTab:
          if (from == _Field.value) {
            _edit(_Editing(key, index, _Field.name));
          } else if (index > 0) {
            _edit(_Editing(key, index - 1, _Field.value));
          } else {
            _edit(null);
          }
        case EditEnd.enter:
        case EditEnd.blur:
          _edit(null);
      }
    }

    final decoration = struck ? TextDecoration.lineThrough : null;
    return DtHover(
      onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, _ruleMenu(rule, declaration, add)),
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: editable && (hovered || !declaration.enabled)
                  ? Center(
                      child: DtCheckbox(
                        size: 11,
                        value: declaration.enabled,
                        onChanged: (on) => inspector.setDeclarationEnabled(rule, declaration, on),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (editing == _Field.name)
                    DtInlineEditor(
                      initial: declaration.name,
                      commitCharacters: const {':'},
                      completions: _completeName,
                      onCancel: () => _edit(null),
                      onCommit: (value, end) {
                        next(value.trim().isEmpty ? EditEnd.enter : end, _Field.name);
                        inspector.editDeclaration(rule, declaration, name: value);
                      },
                    )
                  else
                    _Clickable(
                      onTap: editable ? () => _edit(_Editing(key, index, _Field.name)) : null,
                      child: Opacity(
                        opacity: declaration.enabled && !declaration.overridden ? 1 : 0.6,
                        child: Text(declaration.name, style: context.monoStyle(color: colors.cssProperty, decoration: decoration)),
                      ),
                    ),
                  Text(': ', style: context.monoStyle(color: colors.textStrong)),
                  if (editing == _Field.value)
                    DtInlineEditor(
                      initial: '${declaration.value}${declaration.important ? ' !important' : ''}',
                      commitCharacters: const {';'},
                      completions: (before) => _completeValue(declaration.name, before),
                      onCancel: () => _edit(null),
                      onCommit: (value, end) {
                        next(end, _Field.value);
                        inspector.editDeclaration(rule, declaration, value: value);
                      },
                    )
                  else
                    Opacity(
                      opacity: declaration.enabled && !declaration.overridden ? 1 : 0.6,
                      child: _value(context, rule, declaration, decoration, editable ? () => _edit(_Editing(key, index, _Field.value)) : null),
                    ),
                  if (declaration.important)
                    Text(' !important', style: context.monoStyle(color: colors.textStrong, decoration: decoration)),
                  Text(';', style: context.monoStyle(color: colors.textStrong)),
                  if (invalid)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: DtTooltip(
                        message: declaration.isNameValid ? 'Invalid property value' : 'Invalid property name',
                        child: DtIcon(DtGlyph.warning, size: 11, color: colors.warningIcon),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A value with swatches beside its colours.
  Widget _value(BuildContext context, AppliedRule rule, CssDeclaration declaration, TextDecoration? decoration, VoidCallback? onTap) {
    final colors = context.dt;
    final value = declaration.value;
    final style = context.monoStyle(color: colors.cssValue, decoration: decoration);
    final spans = <InlineSpan>[];
    var position = 0;
    final pattern = RegExp(r'var\(\s*--[\w-]+\s*\)|' + cssColorPattern.pattern);
    final looksForColors = takesColor(declaration.name) || declaration.isCustomProperty;
    for (final match in pattern.allMatches(value)) {
      final text = match.group(0)!;
      final isVariable = text.startsWith('var(');
      final color = isVariable || looksForColors || text.startsWith('#') || text.contains('(') ? inspector.colorOf(text) : null;
      if (color == null && !isVariable) continue;
      spans.add(TextSpan(text: value.substring(position, match.start)));
      position = match.end;
      if (color != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ColorSwatchDot(
              color,
              onTapDown: onTap == null || isVariable
                  ? null
                  : (at) => _pickColor(rule, declaration, match.start, match.end, at),
            ),
          ),
        );
      }
      if (isVariable) {
        final name = RegExp(r'--[\w-]+').firstMatch(text)!.group(0)!;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: DtTooltip(
              message: '$name = ${inspector.variableValue(name) ?? 'not defined'}',
              child: Text(text, style: style),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: text));
      }
    }
    spans.add(TextSpan(text: value.substring(position)));
    return _Clickable(onTap: onTap, child: Text.rich(TextSpan(children: spans), style: style));
  }

  Future<void> _pickColor(AppliedRule rule, CssDeclaration declaration, int start, int end, Offset at) async {
    final original = declaration.value;
    var latest = original.substring(start, end);
    var current = declaration;
    var currentRule = rule;
    var writing = false;
    var pending = false;
    // The latest colour is written once the one before it is in.
    Future<void> write() async {
      if (writing) {
        pending = true;
        return;
      }
      writing = true;
      do {
        pending = false;
        final live = inspector.rules.where((r) => r.identity == currentRule.identity).firstOrNull ?? currentRule;
        final target = live.declarations.where((d) => d.name == declaration.name).firstOrNull ?? current;
        await inspector.editDeclaration(live, target, value: '${original.replaceRange(start, end, latest)}${declaration.important ? ' !important' : ''}');
        currentRule = live;
        current = target;
      } while (pending);
      writing = false;
    }

    await showColorPicker(
      context,
      anchor: at,
      initial: latest,
      onChanged: (color) {
        latest = color;
        write();
      },
    );
  }

  (List<String>, int) _completeName(String before) {
    if (before.isEmpty) return (const [], 0);
    final lower = before.toLowerCase();
    final names = widget.session.cssProperties.keys.where((n) => n.startsWith(lower) && !n.startsWith('-webkit')).toList()..sort();
    if (before.startsWith('--')) {
      return ([
        for (final entry in inspector.computed)
          if (entry.key.startsWith(before)) entry.key,
      ], before.length);
    }
    return (names.take(80).toList(), before.length);
  }

  (List<String>, int) _completeValue(String property, String before) {
    final variable = RegExp(r'var\(\s*(--[\w-]*)$').firstMatch(before);
    if (variable != null) {
      final typed = variable.group(1)!;
      final names = {
        for (final rule in inspector.rules)
          for (final d in rule.declarations)
            if (d.isCustomProperty && d.name.startsWith(typed)) d.name,
      }.toList()..sort();
      return (names, typed.length);
    }
    final typed = RegExp(r'[a-zA-Z-]*$').firstMatch(before)!.group(0)!;
    if (typed.isEmpty) return (const [], 0);
    final lower = typed.toLowerCase();
    final matches = [
      ...keywordsFor(property).where((k) => k.startsWith(lower) && k != lower),
      if (takesColor(property) && lower.length > 1) ...cssNamedColors.keys.where((k) => k.startsWith(lower) && k != lower),
    ];
    return (matches.take(40).toList(), typed.length);
  }

  Widget _newDeclaration(BuildContext context, AppliedRule rule, String key) {
    final editing = _editing!;
    final colors = context.dt;
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (editing.field == _Field.name)
            DtInlineEditor(
              key: ValueKey('new-name ${rule.declarations.length}'),
              initial: '',
              minWidth: 60,
              commitCharacters: const {':'},
              completions: _completeName,
              onCancel: () => _edit(null),
              onCommit: (value, end) {
                final text = value.trim();
                // A whole declaration may have been pasted.
                final colon = text.indexOf(':');
                if (colon > 0) {
                  _edit(null);
                  for (final part in text.split(';')) {
                    final at = part.indexOf(':');
                    if (at > 0) inspector.addDeclaration(rule, part.substring(0, at), part.substring(at + 1));
                  }
                } else if (text.isEmpty || end == EditEnd.blur) {
                  _edit(null);
                } else {
                  _edit(_Editing(key, -1, _Field.value, text));
                }
              },
            )
          else ...[
            Text(editing.newName, style: context.monoStyle(color: colors.cssProperty)),
            Text(': ', style: context.monoStyle(color: colors.textStrong)),
            DtInlineEditor(
              key: ValueKey('new-value ${editing.newName}'),
              initial: '',
              minWidth: 60,
              completionStartsOpen: false,
              commitCharacters: const {';'},
              completions: (before) => _completeValue(editing.newName, before),
              onCancel: () => _edit(null),
              onCommit: (value, end) {
                _edit(end == EditEnd.tab ? _Editing(key, -1, _Field.name) : null);
                inspector.addDeclaration(rule, editing.newName, value);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Clickable extends StatelessWidget {
  const _Clickable({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.text,
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
  );
}

class _TextToggle extends StatelessWidget {
  const _TextToggle(this.label, {required this.active, required this.onTap, required this.tooltip});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return DtTooltip(
      message: tooltip,
      child: DtHover(
        onTap: onTap,
        builder: (context, hovered) => Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.toolbarActive : hovered ? colors.toolbarHover : null,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(label, style: context.uiStyle(color: active ? colors.accent : colors.text, size: 11)),
        ),
      ),
    );
  }
}
