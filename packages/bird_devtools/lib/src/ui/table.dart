import 'package:flutter/widgets.dart';

import '../model/settings.dart';
import 'icons.dart';
import 'menu.dart';
import 'theme.dart';

class DtColumn {
  const DtColumn(this.id, this.label, this.width, {this.alignRight = false, this.minWidth = 36, this.hiddenByDefault = false});
  final String id;
  final String label;
  final double width;
  final bool alignRight;
  final double minWidth;
  final bool hiddenByDefault;
}

/// A table with a header whose columns can be resized, hidden and sorted by.
/// One column, [flexColumn], takes whatever width the others leave.
class DtTable extends StatefulWidget {
  const DtTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.cellBuilder,
    required this.rowBuilder,
    required this.flexColumn,
    required this.settings,
    required this.settingKey,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.headerBuilder,
    this.rowHeight = 22,
    this.controller,
    this.alwaysShown = const {},
  });

  final List<DtColumn> columns;
  final int rowCount;
  final Widget Function(BuildContext context, int row, String column) cellBuilder;

  /// Wraps a row's cells, for its colour and gestures.
  final Widget Function(BuildContext context, int row, Widget cells) rowBuilder;
  final String flexColumn;
  final DevToolsSettings settings;
  final String settingKey;
  final String? sortColumn;
  final bool sortAscending;
  final ValueChanged<String>? onSort;

  /// A header of its own for a column, or null for its label.
  final Widget? Function(BuildContext context, String column, double width)? headerBuilder;
  final double rowHeight;
  final ScrollController? controller;
  final Set<String> alwaysShown;

  @override
  State<DtTable> createState() => _DtTableState();
}

class _DtTableState extends State<DtTable> {
  final Map<String, double> _widths = {};

  double _width(DtColumn column) =>
      _widths[column.id] ?? widget.settings.number('${widget.settingKey}.width.${column.id}', column.width);

  bool _shown(DtColumn column) =>
      column.id == widget.flexColumn ||
      widget.alwaysShown.contains(column.id) ||
      !widget.settings.flag('${widget.settingKey}.hidden.${column.id}', column.hiddenByDefault);

  List<DtMenuEntry> _headerMenu() => [
    for (final column in widget.columns)
      DtMenuItem(
        column.label,
        checked: _shown(column),
        enabled: column.id != widget.flexColumn && !widget.alwaysShown.contains(column.id),
        onSelected: () => setState(() => widget.settings.set('${widget.settingKey}.hidden.${column.id}', _shown(column))),
      ),
    const DtMenuItem.separator(),
    DtMenuItem(
      'Reset Columns',
      onSelected: () => setState(() {
        _widths.clear();
        for (final column in widget.columns) {
          widget.settings
            ..set('${widget.settingKey}.hidden.${column.id}', column.hiddenByDefault)
            ..set('${widget.settingKey}.width.${column.id}', column.width);
        }
      }),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = widget.columns.where(_shown).toList();
        var fixed = 0.0;
        for (final column in columns) {
          if (column.id != widget.flexColumn) fixed += _width(column);
        }
        final flexMinimum = columns.where((c) => c.id == widget.flexColumn).fold(0.0, (_, c) => c.minWidth);
        final flex = (constraints.maxWidth - fixed).clamp(flexMinimum, double.infinity);
        // Columns give way together when the table is too narrow for them.
        final scale = fixed + flex > constraints.maxWidth ? ((constraints.maxWidth - flex) / fixed).clamp(0.4, 1.0) : 1.0;
        final widths = [
          for (final column in columns) column.id == widget.flexColumn ? flex : _width(column) * scale,
        ];
        final total = widths.fold(0.0, (a, b) => a + b);
        Widget scrollable(Widget child) => total <= constraints.maxWidth + 0.5
            ? child
            : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: total, child: child));
        return scrollable(
          Column(
            children: [
              GestureDetector(
                onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, _headerMenu()),
                child: Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: colors.toolbar,
                    border: Border(bottom: BorderSide(color: colors.splitter)),
                  ),
                  child: Row(
                    children: [
                      for (final (index, column) in columns.indexed)
                        SizedBox(width: widths[index], child: _header(context, column, widths[index], index == columns.length - 1)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: widget.controller,
                  itemCount: widget.rowCount,
                  itemExtent: widget.rowHeight,
                  itemBuilder: (context, row) => widget.rowBuilder(
                    context,
                    row,
                    Row(
                      children: [
                        for (final (index, column) in columns.indexed)
                          SizedBox(
                            width: widths[index],
                            height: widget.rowHeight,
                            child: Container(
                              decoration: BoxDecoration(
                                border: index == columns.length - 1
                                    ? null
                                    : Border(right: BorderSide(color: colors.splitter.withValues(alpha: 0.5))),
                              ),
                              alignment: column.alignRight ? Alignment.centerRight : Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: widget.cellBuilder(context, row, column.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, DtColumn column, double width, bool last) {
    final colors = context.dt;
    final custom = widget.headerBuilder?.call(context, column.id, width);
    final label = custom ??
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: column.alignRight ? TextAlign.right : TextAlign.left,
                  style: context.uiStyle(color: colors.text, size: 11),
                ),
              ),
              if (widget.sortColumn == column.id)
                DtIcon(widget.sortAscending ? DtGlyph.sortUp : DtGlyph.sortDown, size: 10, color: colors.textDim),
            ],
          ),
        );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSort == null ? null : () => widget.onSort!(column.id),
            child: Container(
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(border: last ? null : Border(right: BorderSide(color: colors.splitter))),
              child: label,
            ),
          ),
        ),
        if (!last && column.id != widget.flexColumn)
          Positioned(
            right: -3,
            top: 0,
            bottom: 0,
            width: 7,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) => setState(() {
                  _widths[column.id] = (_width(column) + details.delta.dx).clamp(column.minWidth, 1200);
                }),
                onHorizontalDragEnd: (_) {
                  widget.settings.set('${widget.settingKey}.width.${column.id}', _width(column), quiet: true);
                },
              ),
            ),
          ),
      ],
    );
  }
}
