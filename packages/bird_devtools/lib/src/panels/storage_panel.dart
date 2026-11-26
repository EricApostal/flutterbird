import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/session.dart';
import '../model/storage_controller.dart';
import '../ui/icons.dart';
import '../ui/inline_editor.dart';
import '../ui/json_tree.dart';
import '../ui/menu.dart';
import '../ui/table.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The Storage Inspector: cookies, web storage and databases.
class StoragePanel extends StatefulWidget {
  const StoragePanel({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<StoragePanel> {
  final Set<String> _closed = {};
  (String, String)? _editing;
  String _valueFilter = '';
  final FocusNode _focus = FocusNode(debugLabel: 'storage');

  StorageController get storage => widget.session.storage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (storage.selection == null) {
        final cookies = storage.roots[StorageKind.cookies];
        if (cookies != null && cookies.hosts.isNotEmpty) {
          storage.select(StorageSelection(StorageKind.cookies, cookies.hosts.keys.first));
        }
      } else {
        storage.refresh();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: (node, event) {
      if (!node.hasPrimaryFocus || event is! KeyDownEvent) return KeyEventResult.ignored;
      final row = storage.selectedRow;
      if (row != null && (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace)) {
        storage.removeRow(row);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: ListenableBuilder(
      listenable: storage,
      builder: (context, _) => ColoredBox(
        color: context.dt.body,
        child: DtSplit(
          sizeSecond: false,
          initialSize: 220,
          minSize: 140,
          minOther: 300,
          settings: widget.session.settings,
          settingKey: 'storage.treeWidth',
          first: _tree(context),
          second: Column(
            children: [
              _toolbar(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => DtSplit(
                    initialSize: (constraints.maxWidth * 0.34).clamp(200, 420),
                    minSize: 160,
                    minOther: 200,
                    settings: widget.session.settings,
                    settingKey: 'storage.sidebarWidth',
                    showSecond: storage.selectedRow != null,
                    first: _table(context),
                    second: _details(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _treeRow(
    BuildContext context,
    int depth,
    String label,
    DtGlyph glyph, {
    bool? open,
    bool selected = false,
    required VoidCallback onTap,
    VoidCallback? onToggle,
  }) {
    final colors = context.dt;
    return DtHover(
      onTap: onTap,
      builder: (context, hovered) => Container(
        height: 21,
        color: selected ? colors.selection : hovered ? colors.rowHover : null,
        padding: EdgeInsets.only(left: 4 + depth * 14, right: 4),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle ?? onTap,
              child: SizedBox(
                width: 14,
                child: open == null ? null : Center(child: DtIcon(open ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 8, color: colors.textDim)),
              ),
            ),
            DtIcon(glyph, size: 13, color: selected ? colors.selectionText : colors.textDim),
            const SizedBox(width: 5),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.uiStyle(color: selected ? colors.selectionText : colors.text)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tree(BuildContext context) {
    final rows = <Widget>[];
    for (final kind in StorageKind.values) {
      final root = storage.roots[kind];
      if (root == null) continue;
      final open = !_closed.contains(kind.name);
      final glyph = kind == StorageKind.cookies ? DtGlyph.cookie : DtGlyph.database;
      void toggle() => setState(() => open ? _closed.add(kind.name) : _closed.remove(kind.name));
      rows.add(_treeRow(context, 0, kind.label, glyph, open: open, onTap: toggle));
      if (!open) continue;
      for (final host in root.hosts.entries) {
        bool selected(List<String> path) => storage.selection?.key == StorageSelection(kind, host.key, path).key;
        rows.add(
          _treeRow(
            context,
            1,
            host.key,
            DtGlyph.globe,
            open: host.value.isEmpty ? null : !_closed.contains('${kind.name}/${host.key}'),
            selected: selected(const []),
            onTap: () => storage.select(StorageSelection(kind, host.key)),
            onToggle: () => setState(() {
              final key = '${kind.name}/${host.key}';
              _closed.contains(key) ? _closed.remove(key) : _closed.add(key);
            }),
          ),
        );
        if (kind != StorageKind.indexedDb || _closed.contains('${kind.name}/${host.key}')) continue;
        // Databases, and the object stores in each.
        final databases = <String, Set<String>>{};
        for (final raw in host.value) {
          try {
            final path = jsonDecode(raw);
            if (path is List<Object?> && path.isNotEmpty) {
              final stores = databases.putIfAbsent('${path[0]}', () => {});
              if (path.length > 1) stores.add('${path[1]}');
            }
          } on FormatException {
            // Not a path.
          }
        }
        for (final database in databases.entries) {
          rows.add(
            _treeRow(context, 2, database.key, DtGlyph.database,
                selected: selected([database.key]), onTap: () => storage.select(StorageSelection(kind, host.key, [database.key]))),
          );
          for (final store in database.value) {
            rows.add(
              _treeRow(context, 3, store, DtGlyph.folder,
                  selected: selected([database.key, store]), onTap: () => storage.select(StorageSelection(kind, host.key, [database.key, store]))),
            );
          }
        }
      }
    }
    return ColoredBox(
      color: context.dt.sidebar,
      child: rows.isEmpty ? const DtEmptyState('No storage for this page.') : ListView(children: rows),
    );
  }

  Widget _toolbar(BuildContext context) {
    final colors = context.dt;
    return DtToolbar(
      height: 26,
      children: [
        SizedBox(
          width: 240,
          child: DtSearchBox(value: storage.filter, placeholder: 'Filter items', height: 19, onChanged: storage.setFilter),
        ),
        const Spacer(),
        if (storage.error.isNotEmpty)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(storage.error, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.uiStyle(color: colors.errorText, size: 11)),
            ),
          ),
        DtIconButton(DtGlyph.plus, iconSize: 12, tooltip: 'Add Item', onPressed: storage.canAddItem ? storage.addItem : null),
        DtIconButton(DtGlyph.reload, iconSize: 12, tooltip: 'Refresh items', onPressed: storage.refresh),
        DtIconButton(DtGlyph.trash, iconSize: 13, tooltip: 'Delete all', onPressed: storage.canRemoveAll ? storage.removeAll : null),
      ],
    );
  }

  static String _formatCell(String field, Object? value) {
    if (field == 'expires') {
      if (value == 0 || value == null) return 'Session';
      if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true).toIso8601String();
    }
    if (field == 'lastAccessed' && value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true).toIso8601String();
    }
    if (field == 'sameSite' && value == '') return 'None';
    if (value is Map || value is List) return jsonEncode(value);
    return '${value ?? ''}';
  }

  List<DtMenuEntry> _rowMenu(Map<String, Object?> row, String field) {
    final selection = storage.selection!;
    return [
      DtMenuItem('Copy', onSelected: () => Clipboard.setData(ClipboardData(text: _formatCell(field, row[field])))),
      DtMenuItem('Copy Row', onSelected: () => Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(row)))),
      const DtMenuItem.separator(),
      DtMenuItem(
        'Delete “${row['name'] ?? row['db'] ?? row['objectStore'] ?? 'item'}”',
        enabled: selection.kind != StorageKind.indexedDb || selection.path.length != 1,
        onSelected: () => storage.removeRow(row),
      ),
      DtMenuItem('Delete All', enabled: storage.canRemoveAll, onSelected: storage.removeAll),
      if (selection.kind == StorageKind.cookies)
        DtMenuItem('Delete All Session Cookies', onSelected: storage.removeAllSessionCookies),
      if (storage.canAddItem) DtMenuItem('Add Item', onSelected: storage.addItem),
      DtMenuItem('Refresh', onSelected: storage.refresh),
    ];
  }

  Widget _table(BuildContext context) {
    final colors = context.dt;
    final selection = storage.selection;
    if (selection == null) return const DtEmptyState('Select a storage location to see its contents.');
    final rows = storage.visibleRows;
    final fields = storage.fields;
    if (fields.isEmpty) return DtEmptyState(storage.loading ? 'Loading…' : 'No data present for selected host');
    final flex = fields.any((f) => f.name == 'value') ? 'value' : fields.last.name;
    return Column(
      children: [
        Expanded(
          child: DtTable(
            key: ValueKey('${selection.kind.name} ${selection.path.length}'),
            columns: [
              for (final field in fields)
                DtColumn(
                  field.name,
                  field.label,
                  switch (field.name) {
                    'size' => 50,
                    'isHttpOnly' || 'isSecure' => 66,
                    'path' || 'sameSite' => 70,
                    'expires' || 'lastAccessed' => 150,
                    'partitionKey' => 90,
                    _ => 140,
                  },
                  hiddenByDefault: field.name == 'partitionKey' || field.name == 'lastAccessed',
                  minWidth: field.name == flex ? 150 : 36,
                ),
            ],
            flexColumn: flex,
            alwaysShown: const {'name'},
            settings: widget.session.settings,
            settingKey: 'storage.${selection.kind.name}',
            rowCount: rows.length,
            rowHeight: 21,
            rowBuilder: (context, index, cells) {
              final row = rows[index];
              final selected = storage.selectedRow != null && storage.rowKey(storage.selectedRow!) == storage.rowKey(row);
              return DtHover(
                builder: (context, hovered) => Listener(
                  onPointerDown: (_) {
                    if (_editing == null) _focus.requestFocus();
                    storage.selectRow(row);
                  },
                  child: ColoredBox(
                    color: selected ? colors.selection : hovered ? colors.rowHover : index.isOdd ? colors.rowAlternate : colors.body,
                    child: cells,
                  ),
                ),
              );
            },
            cellBuilder: (context, index, column) {
              final row = rows[index];
              final key = storage.rowKey(row);
              final selected = storage.selectedRow != null && storage.rowKey(storage.selectedRow!) == key;
              final field = fields.firstWhere((f) => f.name == column);
              if (_editing == (key, column)) {
                return DtInlineEditor(
                  initial: '${row[column] ?? ''}',
                  maxWidth: 2000,
                  minWidth: 2000,
                  onCancel: () => setState(() => _editing = null),
                  onCommit: (value, end) {
                    setState(() => _editing = null);
                    storage.editCell(row, column, value);
                  },
                );
              }
              return DtHover(
                onDoubleTap: field.editable ? () => setState(() => _editing = (key, column)) : null,
                onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, _rowMenu(row, column)),
                behavior: HitTestBehavior.opaque,
                builder: (context, hovered) => SizedBox.expand(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _formatCell(column, row[column]).replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.monoStyle(color: selected ? colors.selectionText : colors.textStrong),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No data present for selected host', style: context.uiStyle(color: colors.textDim)),
          ),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final row = storage.selectedRow;
    if (row == null) return const SizedBox.shrink();
    final colors = context.dt;
    final value = row['value'];
    final parsed = value is String ? tryDecodeJson(value) : null;
    return ColoredBox(
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DtToolbar(
            height: 26,
            children: [
              Expanded(
                child: DtSearchBox(value: _valueFilter, placeholder: 'Filter values', height: 19, onChanged: (v) => setState(() => _valueFilter = v)),
              ),
              DtIconButton(DtGlyph.close, iconSize: 10, tooltip: 'Close', onPressed: () => storage.selectRow(null)),
            ],
          ),
          Container(
            height: 21,
            color: colors.toolbar,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text('Data', style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
          ),
          Flexible(
            child: DtJsonTree(
              shrinkWrap: false,
              filter: _valueFilter,
              value: {
                for (final field in storage.fields)
                  if (row.containsKey(field.name)) field.name: _display(field.name, row[field.name]),
              },
            ),
          ),
          if (parsed != null) ...[
            Container(
              height: 21,
              color: colors.toolbar,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              child: Text('Parsed Value', style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
            ),
            Expanded(child: DtJsonTree(value: parsed, filter: _valueFilter)),
          ],
        ],
      ),
    );
  }

  Object? _display(String key, Object? value) =>
      key == 'expires' || key == 'lastAccessed' || key == 'creationTime' || key == 'updateTime'
      ? _formatCell(key == 'expires' ? 'expires' : 'lastAccessed', value)
      : value;
}
