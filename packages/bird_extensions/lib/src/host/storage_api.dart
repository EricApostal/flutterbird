import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../extension_registry.dart';
import 'api.dart';

/// `browser.storage`: `local` and `sync` persist to files, `session` lives
/// until the browser closes. There is no cloud, so `sync` is local.
class StorageApi extends ApiNamespace {
  StorageApi(this.root);

  /// Where the files go: `<root>/<uuid>/<area>.json`.
  final Directory root;

  static const Set<String> _areas = {'local', 'sync', 'session', 'managed'};

  final Map<String, Map<String, Object?>> _areasByKey = {};
  final Map<String, Future<void>> _writes = {};

  @override
  String get name => 'storage';

  @override
  String? get requiredPermission => 'storage';

  @override
  Future<Object?> call(ApiCall call) async {
    final area = call.arg(0);
    if (area is! String || !_areas.contains(area)) {
      throw ApiException('Unknown storage area "$area"');
    }

    final uuid = call.extension.uuid;

    // Managed storage is what an administrator sets for an extension. There is
    // no way to set it here, so it reads as empty and refuses writes.
    if (area == 'managed') {
      if (call.method == 'get') return _get(const {}, call.arg(1));
      if (call.method == 'getBytesInUse') return 0;
      throw ApiException('storage.managed is read-only');
    }

    final data = await _load(uuid, area);

    switch (call.method) {
      case 'get':
        return _get(data, call.arg(1));
      case 'set':
        return _notify(call, area, await _set(uuid, area, data, call.arg(1)));
      case 'remove':
        return _notify(
          call,
          area,
          await _remove(uuid, area, data, call.arg(1)),
        );
      case 'clear':
        return _notify(
          call,
          area,
          await _remove(uuid, area, data, data.keys.toList()),
        );
      case 'getBytesInUse':
        return _bytesInUse(data, call.arg(1));
      default:
        throw ApiException('storage.$area.${call.method} is not supported');
    }
  }

  Map<String, Object?> _get(Map<String, Object?> data, Object? keys) {
    if (keys == null) return _copy(data);

    if (keys is String) {
      return {if (data.containsKey(keys)) keys: _clone(data[keys])};
    }

    if (keys is List) {
      return {
        for (final key in keys)
          if (key is String && data.containsKey(key)) key: _clone(data[key]),
      };
    }

    if (keys is Map) {
      // An object names the keys and gives what to use where there is no value.
      return {
        for (final entry in keys.entries)
          entry.key.toString(): data.containsKey(entry.key)
              ? _clone(data[entry.key])
              : entry.value,
      };
    }

    throw ApiException('Invalid keys for storage.get');
  }

  Future<Map<String, Map<String, Object?>>> _set(
    String uuid,
    String area,
    Map<String, Object?> data,
    Object? items,
  ) async {
    if (items is! Map) throw ApiException('storage.set needs an object');

    final changes = <String, Map<String, Object?>>{};
    for (final entry in items.entries) {
      final key = entry.key.toString();
      final value = _clone(entry.value);

      final existed = data.containsKey(key);
      if (existed && _same(data[key], value)) continue;

      changes[key] = {if (existed) 'oldValue': data[key], 'newValue': value};
      data[key] = value;
    }

    if (changes.isNotEmpty) await _save(uuid, area, data);
    return changes;
  }

  Future<Map<String, Map<String, Object?>>> _remove(
    String uuid,
    String area,
    Map<String, Object?> data,
    Object? keys,
  ) async {
    final names = keys is String
        ? [keys]
        : keys is List
        ? keys.whereType<String>().toList()
        : throw ApiException('storage.remove needs a key or a list of keys');

    final changes = <String, Map<String, Object?>>{};
    for (final key in names) {
      if (!data.containsKey(key)) continue;
      changes[key] = {'oldValue': data.remove(key)};
    }

    if (changes.isNotEmpty) await _save(uuid, area, data);
    return changes;
  }

  /// Tells the extension's other contexts what changed, and answers the
  /// caller with nothing, as the real API does.
  Object? _notify(
    ApiCall call,
    String area,
    Map<String, Map<String, Object?>> changes,
  ) {
    if (changes.isNotEmpty) {
      call.host.emit(call.extension.uuid, 'storage.onChanged', [changes, area]);
    }
    return null;
  }

  int _bytesInUse(Map<String, Object?> data, Object? keys) {
    final selected = keys == null
        ? data.keys
        : keys is String
        ? [keys]
        : keys is List
        ? keys.whereType<String>()
        : const <String>[];

    var total = 0;
    for (final key in selected) {
      if (!data.containsKey(key)) continue;
      total +=
          utf8.encode(key).length + utf8.encode(jsonEncode(data[key])).length;
    }
    return total;
  }

  // ------------------------------------------------------------ persistence

  Future<Map<String, Object?>> _load(String uuid, String area) async {
    final key = '$uuid/$area';
    final cached = _areasByKey[key];
    if (cached != null) return cached;

    final data = <String, Object?>{};
    if (area != 'session') {
      final file = _file(uuid, area);
      if (await file.exists()) {
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map) {
            data.addAll(decoded.cast<String, Object?>());
          }
        } on FormatException {
          // Unreadable data is treated as empty rather than failing every
          // call of an extension that stored something once.
        }
      }
    }

    return _areasByKey[key] = data;
  }

  Future<void> _save(String uuid, String area, Map<String, Object?> data) {
    if (area == 'session') return Future<void>.value();

    final key = '$uuid/$area';
    final previous = _writes[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      final file = _file(uuid, area);
      await file.parent.create(recursive: true);

      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(data), flush: true);
      await temporary.rename(file.path);
    });

    _writes[key] = next.catchError((Object _) {});
    return next;
  }

  File _file(String uuid, String area) => File('${root.path}/$uuid/$area.json');

  @override
  Future<void> extensionRemoved(InstalledExtension extension) async {
    for (final area in _areas) {
      _areasByKey.remove('${extension.uuid}/$area');
    }
    await Future.wait(
      _writes.entries
          .where((entry) => entry.key.startsWith('${extension.uuid}/'))
          .map((entry) => entry.value),
    );

    final directory = Directory('${root.path}/${extension.uuid}');
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  // ------------------------------------------------------------ values

  /// A deep copy, so that callers cannot change what is stored.
  static Object? _clone(Object? value) => jsonDecode(jsonEncode(value));

  static Map<String, Object?> _copy(Map<String, Object?> data) =>
      (_clone(data) as Map).cast<String, Object?>();

  static bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
}
