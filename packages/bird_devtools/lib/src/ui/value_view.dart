import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/object_tree.dart';
import '../model/remote_value.dart';
import '../model/session.dart';
import '../protocol/json.dart';
import 'icons.dart';
import 'menu.dart';
import 'theme.dart';
import 'widgets.dart';

const int _maxPreviewItems = 10;
const int _maxStringPreview = 1000;

/// Draws a value the way Firefox's "reps" do: on one line, coloured by kind,
/// saying a little of what is inside.
class ValuePreview {
  ValuePreview(this.colors);

  final DtColors colors;

  TextSpan _span(String text, [Color? color, FontStyle? style]) =>
      TextSpan(text: text, style: TextStyle(color: color, fontStyle: style));

  /// [quoted] is false for a string said at the top level of a log.
  List<InlineSpan> spans(RemoteValue value, {bool quoted = true, int depth = 0}) {
    switch (value.kind) {
      case RemoteKind.undefined:
        return [_span('undefined', colors.textDim)];
      case RemoteKind.nul:
        return [_span('null', colors.textDim)];
      case RemoteKind.boolean:
      case RemoteKind.number:
      case RemoteKind.bigint:
        return [_span(value.describe(), colors.objectNumber)];
      case RemoteKind.string:
        var text = value.value! as String;
        if (!quoted) return [_span(text)];
        final limit = depth > 0 ? 80 : _maxStringPreview;
        if (text.length > limit) text = '${text.substring(0, limit)}…';
        return [_span(RemoteValue.quote(text), colors.objectString)];
      case RemoteKind.object:
        return _object(value, depth);
    }
  }

  List<InlineSpan> _list(
    Iterable<List<InlineSpan>> items,
    int total, {
    String open = '[ ',
    String close = ' ]',
  }) {
    final spans = <InlineSpan>[_span(open)];
    var shown = 0;
    for (final item in items.take(_maxPreviewItems)) {
      if (shown++ > 0) spans.add(_span(', '));
      spans.addAll(item);
    }
    if (total > shown) spans.add(_span(shown > 0 ? ', … ' : '…', colors.textDim));
    spans.add(_span(close));
    return spans;
  }

  /// `<div id="a" class="b">`, coloured as markup.
  List<InlineSpan> element(String name, Map<String, Object?> attributes) => [
    _span('<', colors.textDim),
    _span(name, colors.tag),
    for (final entry in attributes.entries.take(6)) ...[
      _span(' '),
      _span(entry.key, colors.attributeName),
      _span('=', colors.textDim),
      _span('"${_clip('${entry.value}', 60)}"', colors.attributeValue),
    ],
    _span('>', colors.textDim),
  ];

  static String _clip(String text, int length) =>
      text.length > length ? '${text.substring(0, length)}…' : text;

  List<InlineSpan> _object(RemoteValue value, int depth) {
    final preview = value.preview;
    final name = value.className;
    final title = _span(name == 'WindowProxy' ? 'Window' : name, colors.objectClass);

    if (value.isDomNode) {
      final nodeName = preview.str('nodeName').toLowerCase();
      switch (preview.integer('nodeType')) {
        case 1:
          return element(nodeName, preview.obj('attributes'));
        case 3:
          return [
            _span('#text ', colors.objectClass),
            _span(RemoteValue.quote(_clip(preview.str('textContent').trim(), 60)), colors.objectString),
          ];
        case 8:
          return [_span('<!--${_clip(preview.str('textContent'), 60)}-->', colors.comment)];
        case 9:
          return [title, _span(' ${preview.str('location')}', colors.textDim)];
        default:
          return [title];
      }
    }
    if (value.isError) {
      final errorName = preview.str('name', name);
      final message = preview.str('message');
      return [
        _span(errorName, colors.isDark ? colors.errorText : colors.red),
        if (message.isNotEmpty) _span(': $message'),
      ];
    }
    if (value.form['displayString'] case final String display) {
      return [_span(display, colors.objectString)];
    }
    if (value.isFunction) {
      final function = value.form.str('displayName', value.form.str('name'));
      return [
        _span('function ', colors.syntaxKeyword, FontStyle.italic),
        _span('$function()', colors.textStrong, FontStyle.italic),
      ];
    }
    if (name == 'Date' && preview['timestamp'] is num) {
      final date = DateTime.fromMillisecondsSinceEpoch(preview.integer('timestamp'), isUtc: true);
      return [title, _span(' ${date.toIso8601String()}', colors.objectString)];
    }
    switch (preview.str('kind')) {
      case 'ArrayLike':
        final length = preview.integer('length');
        final items = preview.list('items');
        final head = <InlineSpan>[title, _span('($length)', colors.textDim)];
        if (!preview.containsKey('items') || depth >= 1) {
          return depth >= 1 ? [...head] : [...head, _span(' […]')];
        }
        return [
          ...head,
          _span(' '),
          ..._list([for (final item in items) spans(RemoteValue.parse(item), depth: depth + 1)], length),
        ];
      case 'MapLike':
        final size = preview.integer('size');
        final entries = preview.list('entries');
        if (depth >= 1 || entries.isEmpty) return [title, _span('($size)', colors.textDim)];
        return [
          title,
          _span(' '),
          ..._list(
            [
              for (final entry in entries)
                if (entry case [final key, final item])
                  [
                    ...spans(RemoteValue.parse(key), quoted: false, depth: depth + 1),
                    _span(' → ', colors.textDim),
                    ...spans(RemoteValue.parse(item), depth: depth + 1),
                  ],
            ],
            size,
            open: '{ ',
            close: ' }',
          ),
        ];
      case 'Object':
        final properties = preview.obj('ownProperties');
        final total = preview.integer('ownPropertiesLength', properties.length);
        if (depth >= 1 || name == 'WindowProxy') {
          return [title, if (total > 0) _span(' {…}', colors.textDim)];
        }
        final shown = properties.entries.where((e) {
          final descriptor = e.value;
          return descriptor is! Map<String, Object?> || descriptor['enumerable'] != false;
        }).toList();
        if (shown.isEmpty) {
          return [title, _span(total > 0 ? ' {…}' : ' {}', colors.textDim)];
        }
        return [
          title,
          _span(' '),
          ..._list(
            [
              for (final entry in shown)
                [
                  _span(entry.key, colors.objectKey),
                  _span(': '),
                  ..._descriptor(entry.value, depth + 1),
                ],
            ],
            shown.length < total && shown.length >= _maxPreviewItems ? total : shown.length,
            open: '{ ',
            close: ' }',
          ),
        ];
    }
    // What console.table is given comes with its members in place of a preview.
    if (name == 'Array' && value.form['ownProperties'] is Map<String, Object?>) {
      return [title, _span('(${value.form.obj('ownProperties').length})', colors.textDim)];
    }
    return [title];
  }

  List<InlineSpan> _descriptor(Object? descriptor, int depth) {
    if (descriptor is Map<String, Object?> && descriptor.containsKey('value')) {
      return spans(RemoteValue.parse(descriptor['value']), depth: depth);
    }
    return [_span('Getter', colors.textDim)];
  }
}

/// A value that can be opened to see what is in it.
class ValueTreeView extends StatelessWidget {
  const ValueTreeView({
    super.key,
    required this.session,
    required this.tree,
    required this.path,
    required this.entry,
    this.label = false,
    this.quoted = true,
    this.depth = 0,
    this.leading = const [],
    this.trailing = const [],
    this.wrap = true,
    this.headOnly = false,
  });

  final ToolboxSession session;
  final ObjectTree tree;

  /// What tells this line apart from every other in the tree.
  final String path;
  final ObjectEntry entry;

  /// Whether the entry's name is shown before its value.
  final bool label;
  final bool quoted;
  final int depth;

  /// Said before and after the value on its first line.
  final List<InlineSpan> leading;
  final List<InlineSpan> trailing;
  final bool wrap;

  /// Draws the value's own line only, for values set side by side whose
  /// contents go on lines under them all.
  final bool headOnly;

  bool get _expandable => entry.group != null || (entry.value?.isExpandable ?? false);

  static const double indent = 14;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tree,
    builder: (context, _) {
      final open = _expandable && tree.isExpanded(path);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(context, open),
          if (open && !headOnly) ...[
            if (tree.isLoading(path)) _note(context, 'Loading…'),
            if (tree.errorOf(path) case final error?) _note(context, error),
            for (final (index, child) in (tree.childrenOf(path) ?? const <ObjectEntry>[]).indexed)
              ValueTreeView(
                session: session,
                tree: tree,
                path: '$path/$index:${child.name}',
                entry: child,
                label: true,
                depth: depth + 1,
                wrap: wrap,
              ),
          ],
        ],
      );
    },
  );

  Widget _note(BuildContext context, String text) => Padding(
    padding: EdgeInsets.only(left: (depth + 1) * indent + 12),
    child: Text(text, style: context.monoStyle(color: context.dt.textDim)),
  );

  Widget _row(BuildContext context, bool open) {
    final colors = context.dt;
    final preview = ValuePreview(colors);
    final value = entry.value;
    final spans = <InlineSpan>[
      ...leading,
      if (label) ...[
        TextSpan(
          text: entry.name,
          style: TextStyle(
            color: entry.internal
                ? colors.textDim
                : entry.dim
                ? colors.objectKey.withValues(alpha: 0.6)
                : colors.objectKey,
          ),
        ),
        if (entry.group == null) const TextSpan(text: ': '),
      ],
      if (value != null) ...preview.spans(value, quoted: quoted),
      if (value == null && entry.group == null)
        TextSpan(
          text: [
            if (entry.getter != null && entry.getter!.isObject) 'Getter',
            if (entry.setter != null && entry.setter!.isObject) 'Setter',
          ].join(' & '),
          style: TextStyle(color: colors.textDim),
        ),
      if (value != null && value.contentDomReference != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _InspectNodeButton(session: session, reference: value.contentDomReference!),
        ),
      ...trailing,
    ];
    final text = Text.rich(
      TextSpan(children: spans),
      style: context.monoStyle(color: colors.textStrong),
      softWrap: wrap,
      maxLines: wrap ? null : 1,
      overflow: wrap ? TextOverflow.clip : TextOverflow.ellipsis,
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _expandable ? () => tree.toggle(path, entry) : null,
      onSecondaryTapDown: value == null
          ? null
          : (details) => showDtMenu(context, details.globalPosition, [
              DtMenuItem(
                'Copy Value',
                onSelected: () => Clipboard.setData(ClipboardData(text: value.describe())),
              ),
              if (label)
                DtMenuItem(
                  'Copy Property Name',
                  onSelected: () => Clipboard.setData(ClipboardData(text: entry.name)),
                ),
              if (value.contentDomReference case final reference?)
                DtMenuItem(
                  'Reveal in Inspector',
                  onSelected: () {
                    session.selectTool('inspector');
                    session.inspector.selectContentDomReference(reference);
                  },
                ),
            ]),
      child: Padding(
        padding: EdgeInsets.only(left: depth * indent),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_expandable)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: DtIcon(open ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 8, color: colors.textDim),
              )
            else if (depth > 0)
              const SizedBox(width: 12),
            Flexible(child: text),
          ],
        ),
      ),
    );
  }
}

class _InspectNodeButton extends StatelessWidget {
  const _InspectNodeButton({required this.session, required this.reference});

  final ToolboxSession session;
  final Map<String, Object?> reference;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: DtTooltip(
      message: 'Click to select the node in the inspector',
      child: DtHover(
        cursor: SystemMouseCursors.click,
        onEnter: () => session.inspector.highlightContentDomReference(reference),
        onExit: session.inspector.unhighlight,
        onTap: () {
          session.selectTool('inspector');
          session.inspector.selectContentDomReference(reference);
        },
        builder: (context, hovered) => DtIcon(
          DtGlyph.target,
          size: 12,
          color: hovered ? context.dt.accent : context.dt.textDim,
        ),
      ),
    ),
  );
}
