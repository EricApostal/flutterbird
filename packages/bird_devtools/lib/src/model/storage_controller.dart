import 'dart:async';
import 'dart:convert';

import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import 'tool_controller.dart';

enum StorageKind {
  cookies('cookies', 'Cookies'),
  indexedDb('indexed-db', 'Indexed DB'),
  localStorage('local-storage', 'Local Storage'),
  sessionStorage('session-storage', 'Session Storage');

  const StorageKind(this.resourceType, this.label);
  final String resourceType;
  final String label;
}

class StorageRoot {
  StorageRoot(this.actor, this.hosts);
  final String actor;

  /// Each host with, for a database, the paths under it.
  final Map<String, List<String>> hosts;
}

class StorageField {
  const StorageField(this.name, {this.editable = false});
  final String name;
  final bool editable;

  String get label => switch (name) {
    'name' => 'Name',
    'value' => 'Value',
    'host' => 'Domain',
    'path' => 'Path',
    'expires' => 'Expires / Max-Age',
    'size' => 'Size',
    'isHttpOnly' => 'HttpOnly',
    'isSecure' => 'Secure',
    'sameSite' => 'SameSite',
    'lastAccessed' => 'Last Accessed',
    'partitionKey' => 'Partition Key',
    'db' => 'Database Name',
    'storage' => 'Storage',
    'origin' => 'Origin',
    'version' => 'Version',
    'objectStores' => 'Object Stores',
    'objectStore' => 'Object Store Name',
    'keyPath' => 'Key Path',
    'autoIncrement' => 'Auto Increment',
    'indexes' => 'Indexes',
    _ => name,
  };
}

class StorageSelection {
  const StorageSelection(this.kind, [this.host, this.path = const []]);
  final StorageKind kind;
  final String? host;

  /// Database, then object store.
  final List<String> path;

  String get key => '${kind.name}|${host ?? ''}|${path.join('\u0001')}';
}

class StorageController extends ToolController {
  StorageController(super.session);

  final Map<StorageKind, StorageRoot> roots = {};
  final Map<StorageKind, void Function()> _listeners = {};

  StorageSelection? selection;
  List<StorageField> fields = const [];
  List<Map<String, Object?>> rows = const [];
  Map<String, Object?>? selectedRow;
  String filter = '';
  String error = '';
  bool loading = false;
  int _generation = 0;
  Timer? _refreshTimer;

  @override
  void onTargetDestroyed() {
    _generation++;
    roots.clear();
    for (final dispose in _listeners.values) {
      dispose();
    }
    _listeners.clear();
    rows = const [];
    selectedRow = null;
    changed();
  }

  @override
  void onResources(String type, List<Map<String, Object?>> resources) {
    final kind = StorageKind.values
        .where((kind) => kind.resourceType == type)
        .firstOrNull;
    if (kind == null) return;
    for (final resource in resources) {
      final actor = resource.str('actor');
      final hosts = <String, List<String>>{};
      for (final entry in resource.obj('hosts').entries) {
        final paths = entry.value;
        hosts[entry.key] = [
          if (paths is List<Object?>)
            for (final path in paths)
              if (path is String) path,
        ];
      }
      roots[kind] = StorageRoot(actor, hosts);
      _listeners[kind]?.call();
      _listeners[kind] = session.connection.listen(actor, (packet) {
        final type = packet['type'];
        if (type != 'storesUpdate' && type != 'storesCleared') return;
        if (this.selection?.kind != kind) return;
        _refreshTimer?.cancel();
        _refreshTimer = Timer(const Duration(milliseconds: 150), refresh);
      });
    }
    final selection = this.selection;
    if (selection != null && selection.kind == kind) {
      // Keep looking at the same kind of storage on the new page.
      final root = roots[kind]!;
      select(
        StorageSelection(
          kind,
          root.hosts.containsKey(selection.host)
              ? selection.host
              : root.hosts.keys.firstOrNull,
        ),
      );
    }
    changed();
  }

  void select(StorageSelection next) {
    final same = selection?.key == next.key;
    selection = next;
    if (!same) {
      selectedRow = null;
      rows = const [];
      fields = const [];
    }
    changed();
    refresh();
  }

  void setFilter(String value) {
    filter = value;
    changed();
  }

  void selectRow(Map<String, Object?>? row) {
    selectedRow = row;
    changed();
  }

  List<Map<String, Object?>> get visibleRows {
    final needle = filter.toLowerCase();
    if (needle.isEmpty) return rows;
    return [
      for (final row in rows)
        if (row.values.any((value) => '$value'.toLowerCase().contains(needle)))
          row,
    ];
  }

  /// What identifies a row, for keeping it selected and for removing it.
  String rowKey(Map<String, Object?> row) {
    for (final key in ['uniqueKey', 'name', 'db', 'objectStore']) {
      if (row[key] case final String value) return value;
    }
    return jsonEncode(row);
  }

  Future<void> refresh() async {
    final selection = this.selection;
    final root = selection == null ? null : roots[selection.kind];
    final generation = ++_generation;
    if (selection == null || root == null || selection.host == null) {
      rows = const [];
      fields = const [];
      changed();
      return;
    }
    loading = true;
    changed();
    try {
      final isDatabase = selection.kind == StorageKind.indexedDb;
      final fieldResponse = await session.connection.request(
        root.actor,
        'getFields',
        {
          if (isDatabase && selection.path.isNotEmpty)
            'subType': selection.path.length == 1 ? 'database' : 'object store',
        },
      );
      final nextRows = <Map<String, Object?>>[];
      // The server hands out fifty at a time.
      while (nextRows.length < 2000) {
        final response = await session.connection.request(
          root.actor,
          'getStoreObjects',
          {
            'host': selection.host,
            if (isDatabase && selection.path.isNotEmpty)
              'names': [jsonEncode(selection.path)],
            'options': {'offset': nextRows.length, 'size': 50},
          },
        );
        final page = response.maps('data');
        nextRows.addAll(page);
        if (page.isEmpty || nextRows.length >= response.integer('total')) break;
      }
      if (generation != _generation) return;
      fields = [
        for (final field in fieldResponse.maps('value'))
          if (!field.flag('hidden') && !field.flag('private'))
            StorageField(field.str('name'), editable: field.flag('editable')),
      ];
      rows = nextRows;
      final held = selectedRow == null ? null : rowKey(selectedRow!);
      selectedRow = nextRows.where((row) => rowKey(row) == held).firstOrNull;
      error = '';
    } on RdpError catch (failure) {
      if (generation != _generation) return;
      rows = const [];
      error = failure.message;
    }
    loading = false;
    changed();
  }

  bool get canAddItem =>
      selection?.host != null && selection!.kind != StorageKind.indexedDb;

  Future<void> _act(String type, Map<String, Object?> parameters) async {
    final root = roots[selection?.kind];
    if (root == null) return;
    try {
      final response = await session.connection.request(
        root.actor,
        type,
        parameters,
      );
      error = response.str('errorString');
    } on RdpError catch (failure) {
      error = failure.message;
    }
    await refresh();
  }

  Future<void> addItem() async {
    final selection = this.selection;
    if (selection == null || !canAddItem) return;
    final guid = 'new item ${DateTime.now().millisecondsSinceEpoch % 100000}';
    await _act('addItem', {'guid': guid, 'host': selection.host});
  }

  Future<void> editCell(
    Map<String, Object?> row,
    String field,
    String value,
  ) async {
    final selection = this.selection;
    if (selection == null) return;
    final old = '${row[field] ?? ''}';
    if (old == value) return;
    final items = {...row, field: value};
    if (selection.kind == StorageKind.cookies) {
      items['uniqueKey'] = row['uniqueKey'];
      await _act('editItem', {
        'data': {
          'field': field,
          'oldValue': old,
          'newValue': value,
          'items': items,
        },
      });
    } else {
      await _act('editItem', {
        'data': {
          'host': selection.host,
          'field': field,
          'oldValue': old,
          'items': items,
        },
      });
    }
  }

  Future<void> removeRow(Map<String, Object?> row) async {
    final selection = this.selection;
    if (selection == null) return;
    if (selection.kind == StorageKind.indexedDb) {
      if (selection.path.isEmpty) {
        await _act('removeDatabase', {
          'host': selection.host,
          'name': row['db'] ?? rowKey(row),
        });
      } else if (selection.path.length == 2) {
        await _act('removeItem', {
          'host': selection.host,
          'name': jsonEncode([...selection.path, row['name']]),
        });
      }
      return;
    }
    await _act('removeItem', {'host': selection.host, 'name': rowKey(row)});
  }

  bool get canRemoveAll =>
      selection?.host != null &&
      (selection!.kind != StorageKind.indexedDb || selection!.path.length == 2);

  Future<void> removeAll() async {
    final selection = this.selection;
    if (selection == null || !canRemoveAll) return;
    await _act('removeAll', {
      'host': selection.host,
      if (selection.kind == StorageKind.indexedDb)
        'name': jsonEncode(selection.path),
    });
  }

  Future<void> removeAllSessionCookies() async {
    final selection = this.selection;
    if (selection?.kind != StorageKind.cookies) return;
    await _act('removeAllSessionCookies', {'host': selection!.host});
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final dispose in _listeners.values) {
      dispose();
    }
    super.dispose();
  }
}
