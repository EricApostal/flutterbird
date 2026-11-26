import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import 'remote_value.dart';
import 'session.dart';
import 'tool_controller.dart';

/// One line under an opened object.
class ObjectEntry {
  const ObjectEntry(
    this.name, {
    this.value,
    this.getter,
    this.setter,
    this.dim = false,
    this.internal = false,
    this.group,
  });

  factory ObjectEntry.property(RemoteProperty property) => ObjectEntry(
    property.name,
    value: property.value,
    getter: property.getter,
    setter: property.setter,
    dim: !property.enumerable,
  );

  final String name;
  final RemoteValue? value;
  final RemoteValue? getter;
  final RemoteValue? setter;
  final bool dim;

  /// Not a property of the object, as `<prototype>` is not.
  final bool internal;

  /// For a line that only holds other lines, such as `<entries>`.
  final List<ObjectEntry>? group;
}

/// Which objects are open and what was found in them, kept apart from the
/// widgets so that it outlasts them.
class ObjectTree extends ToolController {
  ObjectTree(super.session);

  static const int _bucket = 100;
  static const int _maxProperties = 5000;

  final Set<String> _expanded = {};
  final Map<String, List<ObjectEntry>> _children = {};
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};

  bool isExpanded(String path) => _expanded.contains(path);
  List<ObjectEntry>? childrenOf(String path) => _children[path];
  bool isLoading(String path) => _loading.contains(path);
  String? errorOf(String path) => _errors[path];

  void clear() {
    _expanded.clear();
    _children.clear();
    _loading.clear();
    _errors.clear();
    changed();
  }

  void toggle(String path, ObjectEntry entry) {
    if (!_expanded.remove(path)) {
      _expanded.add(path);
      if (!_children.containsKey(path)) _load(path, entry);
    }
    changed();
  }

  Future<void> _load(String path, ObjectEntry entry) async {
    if (entry.group case final group?) {
      _children[path] = _bucketed(group);
      return;
    }
    final value = entry.value;
    final actor = value?.actor;
    if (value == null || actor == null || !_loading.add(path)) return;
    changed();
    try {
      _children[path] = await _properties(session, value, actor);
      _errors.remove(path);
    } on RdpError catch (error) {
      _errors[path] = error.isUnknownActor
          ? 'This object is no longer available.'
          : error.message;
    }
    _loading.remove(path);
    changed();
  }

  /// A long run of lines is split into ranges, as Firefox does.
  static List<ObjectEntry> _bucketed(List<ObjectEntry> entries) {
    if (entries.length <= _bucket) return entries;
    var size = _bucket;
    while (entries.length > size * _bucket) {
      size *= _bucket;
    }
    return [
      for (var start = 0; start < entries.length; start += size)
        ObjectEntry(
          '[$start…${(start + size).clamp(0, entries.length) - 1}]',
          group: entries.sublist(start, (start + size).clamp(0, entries.length)),
          internal: true,
        ),
    ];
  }

  static Future<List<ObjectEntry>> _properties(
    ToolboxSession session,
    RemoteValue value,
    String actor,
  ) async {
    final connection = session.connection;
    final iterator = (await connection.request(actor, 'enumProperties', {
      'options': {'ignoreNonIndexedProperties': false},
    })).obj('iterator');
    final count = iterator.integer('count').clamp(0, _maxProperties);
    final own = (await connection.request(iterator.str('actor'), 'slice', {
      'start': 0,
      'count': count,
    })).obj('ownProperties');
    connection.notify(iterator.str('actor'), 'release');

    final indexed = <ObjectEntry>[];
    final named = <ObjectEntry>[];
    for (final property in own.entries) {
      final entry = ObjectEntry.property(
        RemoteProperty.parse(property.key, property.value),
      );
      (int.tryParse(property.key) != null ? indexed : named).add(entry);
    }
    indexed.sort((a, b) => int.parse(a.name).compareTo(int.parse(b.name)));

    final preview = value.preview;
    final entries = <ObjectEntry>[
      ..._bucketed(indexed),
      ...named,
    ];
    if (preview.str('kind') == 'MapLike') {
      final held = preview.list('entries');
      entries.insert(
        0,
        ObjectEntry(
          '<entries>',
          internal: true,
          group: [
            for (var i = 0; i < held.length; i++)
              if (held[i] case [final key, final item])
                ObjectEntry(
                  RemoteValue.parse(key).describe(),
                  value: RemoteValue.parse(item),
                ),
          ],
        ),
      );
    } else if (preview.str('kind') == 'ArrayLike' && indexed.isEmpty) {
      // A set's members are not properties; the preview lists some of them.
      final held = preview.list('items');
      if (held.isNotEmpty) {
        entries.insert(
          0,
          ObjectEntry(
            '<entries>',
            internal: true,
            group: [
              for (var i = 0; i < held.length; i++)
                ObjectEntry('$i', value: RemoteValue.parse(held[i])),
            ],
          ),
        );
      }
    }
    final prototype = await connection.request(actor, 'prototype');
    if (prototype.containsKey('prototype')) {
      final parent = RemoteValue.parse(prototype['prototype']);
      if (parent.isObject) {
        entries.add(ObjectEntry('<prototype>', value: parent, internal: true));
      }
    }
    return entries;
  }

  @override
  void onTargetDestroyed() => clear();
}
