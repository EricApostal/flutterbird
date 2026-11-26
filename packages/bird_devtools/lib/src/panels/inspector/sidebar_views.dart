import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/dom.dart';
import '../../model/inspector_controller.dart';
import '../../model/session.dart';
import '../../model/styles.dart';
import '../../protocol/json.dart';
import '../../ui/color_picker.dart';
import '../../ui/icons.dart';
import '../../ui/inline_editor.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../../util/css_color.dart';
import '../../util/css_values.dart';

/// The Computed view: what each property came to.
class ComputedView extends StatefulWidget {
  const ComputedView({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<ComputedView> createState() => _ComputedViewState();
}

class _ComputedViewState extends State<ComputedView> {
  String _filter = '';
  final Set<String> _open = {};
  final FocusNode _focus = FocusNode(debugLabel: 'computed');

  InspectorController get inspector => widget.session.inspector;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// The declarations that had a say in a property, the winner first.
  List<(AppliedRule, CssDeclaration)> _matches(String property) => [
    for (final rule in inspector.rules)
      for (final declaration in rule.declarations)
        if (declaration.enabled &&
            declarationReaches(rule, declaration) &&
            longhandsOf(declaration.name).contains(property))
          (rule, declaration),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: inspector,
    builder: (context, _) {
      final colors = context.dt;
      final authored = <String>{
        for (final rule in inspector.rules)
          for (final declaration in rule.declarations)
            if (declaration.enabled && declarationReaches(rule, declaration)) ...longhandsOf(declaration.name),
      };
      final needle = _filter.toLowerCase();
      final browserStyles = inspector.showBrowserStyles;
      final entries = [
        for (final entry in inspector.computed)
          if ((browserStyles || authored.contains(entry.key)) &&
              (needle.isEmpty || entry.key.contains(needle) || entry.value.toLowerCase().contains(needle)))
            entry,
      ];
      return ColoredBox(
        color: colors.sidebar,
        child: Column(
          children: [
            DtToolbar(
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
                const SizedBox(width: 8),
                DtCheckbox(
                  label: 'Browser Styles',
                  value: browserStyles,
                  onChanged: inspector.setShowBrowserStyles,
                ),
                const SizedBox(width: 4),
              ],
            ),
            Expanded(
              child: entries.isEmpty
                  ? const DtEmptyState('No CSS properties found.')
                  : SelectableRegion(
                      focusNode: _focus,
                      selectionControls: emptyTextSelectionControls,
                      contextMenuBuilder: (context, state) => const SizedBox.shrink(),
                      child: ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) => _row(context, entries[index], index),
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget _row(BuildContext context, MapEntry<String, String> entry, int index) {
    final colors = context.dt;
    final open = _open.contains(entry.key);
    final color = takesColor(entry.key) ? parseCssColor(entry.value) : null;
    final matches = open ? _matches(entry.key) : const <(AppliedRule, CssDeclaration)>[];
    return Container(
      color: index.isOdd ? colors.rowAlternate : null,
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => open ? _open.remove(entry.key) : _open.add(entry.key)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 5),
                  child: DtIcon(open ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 8, color: colors.textDim),
                ),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${entry.key}: ', style: context.monoStyle(color: colors.cssProperty)),
                      if (color != null) ColorSwatchDot(color),
                      Text(entry.value, style: context.monoStyle(color: colors.cssValue)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (open)
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text('No rule declares this property.', style: context.uiStyle(color: colors.textDim, size: 11)),
              )
            else
              for (final (rule, declaration) in matches)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rule.selectorText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.monoStyle(color: colors.textStrong),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          declaration.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.monoStyle(
                            color: declaration.overridden ? colors.textDim : colors.cssValue,
                            decoration: declaration.overridden ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

/// The Layout view: flexbox, grid and the box model.
class LayoutView extends StatefulWidget {
  const LayoutView({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<LayoutView> createState() => _LayoutViewState();
}

class _LayoutViewState extends State<LayoutView> {
  InspectorController get inspector => widget.session.inspector;

  bool _open(String section) => !widget.session.settings.flag('layout.closed.$section');

  void _toggle(String section) {
    widget.session.settings.set('layout.closed.$section', _open(section), quiet: true);
    setState(() {});
  }

  Widget _section(String id, String title, Widget child) => DtAccordion(
    title: title,
    expanded: _open(id),
    onToggle: () => _toggle(id),
    child: child,
  );

  Widget _nodeLink(BuildContext context, String actor) {
    final node = inspector.nodeFor(actor);
    if (node == null) return Text('element', style: context.monoStyle(color: context.dt.textDim));
    return DtHover(
      cursor: SystemMouseCursors.click,
      onEnter: () => inspector.highlight(node),
      onExit: inspector.unhighlight,
      onTap: () => inspector.select(node, reveal: true),
      builder: (context, hovered) => Text(
        node.selectorLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.monoStyle(color: context.dt.tag, decoration: hovered ? TextDecoration.underline : null),
      ),
    );
  }

  Widget _message(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.all(10),
    child: Text(text, textAlign: TextAlign.center, style: context.uiStyle(color: context.dt.textDim)),
  );

  Widget _property(BuildContext context, String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
    child: Row(
      children: [
        Expanded(child: Text(name, style: context.monoStyle(color: context.dt.cssProperty))),
        Expanded(child: Text(value, style: context.monoStyle(color: context.dt.textStrong))),
      ],
    ),
  );

  Widget _flex(BuildContext context) {
    final container = inspector.flexContainer ?? inspector.parentFlexContainer;
    if (container == null) return _message(context, 'Select a Flex container or item to continue.');
    final selected = inspector.selectedElement?.actor;
    final item = inspector.parentFlexContainer?.items.where((i) => i.nodeActor == selected).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: Row(
            children: [
              DtCheckbox(
                value: inspector.flexHighlighted,
                tooltip: 'Overlay flexbox',
                onChanged: (on) => inspector.toggleFlexHighlighter(container.nodeActor, on),
              ),
              const SizedBox(width: 6),
              Text('Flex Container  ', style: context.uiStyle(color: context.dt.textStrong, weight: FontWeight.w600)),
              Flexible(child: _nodeLink(context, container.nodeActor)),
            ],
          ),
        ),
        for (final entry in container.properties.entries) _property(context, entry.key, '${entry.value}'),
        if (item != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
            child: Text('Flex Item', style: context.uiStyle(color: context.dt.textStrong, weight: FontWeight.w600)),
          ),
          for (final entry in item.properties.entries) _property(context, entry.key, '${entry.value}'),
          _property(context, 'base size', _size(item.sizing, 'mainBaseSize')),
          _property(context, 'flexibility', _size(item.sizing, 'mainDeltaSize')),
          _property(context, 'min size', _size(item.sizing, 'mainMinSize')),
          _property(context, 'line state', item.sizing.str('lineGrowthState')),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
          child: Text('Flex Items (${container.items.length})', style: context.uiStyle(color: context.dt.textDim)),
        ),
        for (final (index, flexItem) in container.items.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
            child: Row(
              children: [
                SizedBox(width: 22, child: Text('${index + 1}', style: context.uiStyle(color: context.dt.textDim))),
                Expanded(child: _nodeLink(context, flexItem.nodeActor)),
              ],
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  static String _size(Map<String, Object?> sizing, String key) {
    final value = sizing.number(key);
    return '${value == value.roundToDouble() ? value.round() : value.toStringAsFixed(2)}px';
  }

  Widget _grid(BuildContext context) {
    if (inspector.grids.isEmpty) return _message(context, 'CSS Grid is not in use on this page');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: Text('Overlay Grid', style: context.uiStyle(color: context.dt.textStrong, weight: FontWeight.w600)),
        ),
        for (final grid in inspector.grids)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(
              children: [
                DtCheckbox(
                  value: inspector.highlightedGrids.contains(grid.nodeActor),
                  onChanged: (on) => inspector.toggleGridHighlighter(grid.nodeActor, on),
                ),
                const SizedBox(width: 6),
                Flexible(child: _nodeLink(context, grid.nodeActor)),
                const SizedBox(width: 6),
                const ColorSwatchDot(DtColors.layoutMark),
                Text('${grid.columns} × ${grid.rows}', style: context.uiStyle(color: context.dt.textDim, size: 11)),
              ],
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _boxModel(BuildContext context) {
    final box = inspector.boxModel;
    final element = inspector.selectedElement;
    if (box.isEmpty || element == null) return _message(context, 'No box model for this node.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: BoxModelDiagram(
            box: box,
            onEdit: element.isElement ? (property, value) => _setInline(element, property, value) : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text('${_pixels(box, 'width')}×${_pixels(box, 'height')}', style: context.monoStyle(color: context.dt.textStrong)),
              const Spacer(),
              Text(box.str('position'), style: context.monoStyle(color: context.dt.textDim)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        DtAccordion(
          title: 'Box Model Properties',
          header: false,
          expanded: _open('boxProperties'),
          onToggle: () => _toggle('boxProperties'),
          child: Column(
            children: [
              for (final name in const ['box-sizing', 'display', 'float', 'line-height', 'position', 'z-index'])
                _property(context, name, '${box[name] ?? ''}'),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  void _setInline(DomNode element, String property, String value) {
    final rule = inspector.rules.where((r) => r.isElementStyle && r.inheritedFrom == null).firstOrNull;
    if (rule == null) return;
    var text = value.trim();
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) text = '${text}px';
    final existing = rule.declarations.where((d) => d.name == property).firstOrNull;
    if (existing != null) {
      inspector.editDeclaration(rule, existing, value: text);
    } else if (text.isNotEmpty) {
      inspector.addDeclaration(rule, property, text);
    }
  }

  static String _pixels(Map<String, Object?> box, String key) {
    final value = box.number(key);
    return value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: inspector,
    builder: (context, _) => ColoredBox(
      color: context.dt.sidebar,
      child: ListView(
        children: [
          _section('flex', 'Flexbox', _flex(context)),
          _section('grid', 'Grid', _grid(context)),
          _section('box', 'Box Model', _boxModel(context)),
        ],
      ),
    ),
  );
}

/// The nested boxes of margin, border, padding and content.
class BoxModelDiagram extends StatefulWidget {
  const BoxModelDiagram({super.key, required this.box, this.onEdit});

  final Map<String, Object?> box;
  final void Function(String property, String value)? onEdit;

  @override
  State<BoxModelDiagram> createState() => _BoxModelDiagramState();
}

class _BoxModelDiagramState extends State<BoxModelDiagram> {
  String? _editing;

  String _number(String key) {
    final text = '${widget.box[key] ?? '0'}'.replaceAll('px', '');
    final value = double.tryParse(text);
    if (value == null) return text;
    if (value == 0) return '0';
    return value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);
  }

  Widget _value(BuildContext context, String property) {
    if (_editing == property) {
      return SizedBox(
        width: 40,
        child: DtInlineEditor(
          initial: _number(property),
          maxWidth: 40,
          onCancel: () => setState(() => _editing = null),
          onCommit: (value, end) {
            setState(() => _editing = null);
            if (value != _number(property)) widget.onEdit?.call(property, value);
          },
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: widget.onEdit == null ? null : () => setState(() => _editing = property),
      child: DtTooltip(
        message: property,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 22),
          child: Text(
            _number(property),
            textAlign: TextAlign.center,
            style: context.monoStyle(color: const Color(0xFF131417), size: 10),
          ),
        ),
      ),
    );
  }

  Widget _ring(BuildContext context, String label, String prefix, String suffix, Color color, Widget child) => Container(
    decoration: BoxDecoration(color: color, border: Border.all(color: const Color(0x66000000))),
    child: Stack(
      children: [
        Positioned(
          left: 3,
          top: 1,
          child: Text(label, style: context.uiStyle(color: const Color(0xFF35383E), size: 9)),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 17, child: Center(child: _value(context, '$prefix-top$suffix'))),
            Row(
              children: [
                SizedBox(width: 30, child: Center(child: _value(context, '$prefix-left$suffix'))),
                Expanded(child: child),
                SizedBox(width: 30, child: Center(child: _value(context, '$prefix-right$suffix'))),
              ],
            ),
            SizedBox(height: 17, child: Center(child: _value(context, '$prefix-bottom$suffix'))),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = widget.box.number('width');
    final height = widget.box.number('height');
    String size(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);
    final content = Container(
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFFB8CBEE), border: Border.all(color: const Color(0x66000000))),
      child: Text('${size(width)}×${size(height)}', style: context.monoStyle(color: const Color(0xFF131417), size: 10)),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: _ring(
          context,
          'margin',
          'margin',
          '',
          const Color(0xFFF2E0B9),
          _ring(
            context,
            'border',
            'border',
            '-width',
            const Color(0xFFCDCFD4),
            _ring(context, 'padding', 'padding', '', const Color(0xFFBFE2D3), content),
          ),
        ),
      ),
    );
  }
}

/// The Fonts view: the fonts the selected element is drawn with.
class FontsView extends StatelessWidget {
  const FontsView({super.key, required this.session});

  final ToolboxSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.inspector,
    builder: (context, _) {
      final colors = context.dt;
      final inspector = session.inspector;
      String computed(String name) => inspector.computed.where((e) => e.key == name).firstOrNull?.value ?? '';
      return ColoredBox(
        color: colors.sidebar,
        child: ListView(
          children: [
            DtAccordion(
              title: 'Fonts Used',
              expanded: true,
              onToggle: () {},
              child: inspector.fonts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('No fonts were found for the current element.', style: context.uiStyle(color: colors.textDim)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final font in inspector.fonts)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(font.name, style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
                                Text('weight ${font.weight}', style: context.uiStyle(color: colors.textDim, size: 11)),
                                Text(
                                  'AaBbCc 123',
                                  style: context.uiStyle(
                                    color: colors.textStrong,
                                    size: 20,
                                  ).copyWith(fontFamily: font.name),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            DtAccordion(
              title: 'Font Properties',
              expanded: true,
              onToggle: () {},
              child: Column(
                children: [
                  for (final name in const ['font-family', 'font-size', 'font-weight', 'font-style', 'line-height', 'letter-spacing'])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 110, child: Text(name, style: context.monoStyle(color: colors.cssProperty))),
                          Expanded(child: Text(computed(name), style: context.monoStyle(color: colors.textStrong))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The Changes view: what has been edited through the tools, as a diff.
class ChangesView extends StatelessWidget {
  const ChangesView({super.key, required this.session});

  final ToolboxSession session;

  static String _diff(List<StyleChange> changes) {
    final out = StringBuffer();
    String? source;
    String? selector;
    for (final change in changes) {
      if (change.source != source) {
        out.writeln('/* ${change.source} */');
        source = change.source;
        selector = null;
      }
      if (change.selector != selector) {
        out.writeln('${change.selector} {');
        selector = change.selector;
      }
      if (change.before != null) out.writeln('-  ${change.before}');
      if (change.after != null) out.writeln('+  ${change.after}');
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.inspector,
    builder: (context, _) {
      final colors = context.dt;
      final changes = session.inspector.changes.toList()
        ..sort((a, b) {
          final bySource = a.source.compareTo(b.source);
          return bySource != 0 ? bySource : a.selector.compareTo(b.selector);
        });
      if (changes.isEmpty) {
        return ColoredBox(
          color: colors.sidebar,
          child: const DtEmptyState('No changes found.', detail: 'Edits to CSS made in the Rules view appear here.'),
        );
      }
      Widget line(String sign, String text, Color background) => Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 18, child: Text(sign, style: context.monoStyle(color: colors.textStrong))),
            Expanded(child: Text(text, style: context.monoStyle(color: colors.textStrong))),
          ],
        ),
      );
      final rows = <Widget>[];
      String? source;
      String? selector;
      for (final change in changes) {
        if (change.source != source) {
          source = change.source;
          selector = null;
          rows.add(
            Container(
              color: colors.toolbar,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(source, style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
            ),
          );
        }
        if (change.selector != selector) {
          selector = change.selector;
          rows.add(line('', '$selector {', const Color(0x00000000)));
        }
        if (change.before != null) rows.add(line('−', '  ${change.before}', colors.errorBackground));
        if (change.after != null) {
          rows.add(line('+', '  ${change.after}', colors.isDark ? const Color(0xFF1B342B) : const Color(0xFFE0F3E9)));
        }
      }
      return ColoredBox(
        color: colors.sidebar,
        child: Column(
          children: [
            DtToolbar(
              height: 25,
              children: [
                const Spacer(),
                DtButton(
                  'Copy All Changes',
                  glyph: DtGlyph.copy,
                  onPressed: () => Clipboard.setData(ClipboardData(text: _diff(changes))),
                ),
              ],
            ),
            Expanded(child: ListView(children: rows)),
          ],
        ),
      );
    },
  );
}
