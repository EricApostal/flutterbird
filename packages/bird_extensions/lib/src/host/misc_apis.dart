import 'dart:async';
import 'dart:io';

import '../extension_registry.dart';
import '../manifest.dart';
import '../match_pattern.dart';
import 'api.dart';

// ---------------------------------------------------------------- menus

/// `browser.menus` (and `contextMenus`): the items an extension adds to the
/// browser's context menu. They are kept here for the app to show.
class MenusApi extends ApiNamespace {
  final Map<String, Map<Object, Map<String, Object?>>> _items = {};
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  @override
  String get name => 'menus';

  @override
  String? get requiredPermission => null;

  /// The uuid of an extension whose items changed.
  Stream<String> get changes => _changes.stream;

  /// The menu items [uuid] has made, in the order it made them.
  List<Map<String, Object?>> itemsOf(String uuid) => [...?_items[uuid]?.values];

  @override
  Future<void> extensionRemoved(InstalledExtension extension) async {
    _items.remove(extension.uuid);
    _changes.add(extension.uuid);
  }

  @override
  Future<Object?> call(ApiCall call) async {
    final uuid = call.extension.uuid;
    final items = _items[uuid] ??= {};

    switch (call.method) {
      case 'create':
        final properties = call.arg(0);
        final menuId = properties is Map ? properties['id'] : null;
        if (properties is! Map || menuId is! Object) {
          throw ApiException('menus.create needs an id');
        }
        items[menuId] = properties.cast<String, Object?>();
      case 'update':
        final id = call.arg(0);
        final changes = call.arg(1);
        final existing = items[id];
        if (existing == null || changes is! Map) {
          throw ApiException('No menu item with id "$id"');
        }
        existing.addAll(changes.cast<String, Object?>());
      case 'remove':
        final id = call.arg(0);
        if (items.remove(id) == null) {
          throw ApiException('No menu item with id "$id"');
        }
        items.removeWhere((_, item) => item['parentId'] == id);
      case 'removeAll':
        items.clear();
      default:
        throw ApiException('menus.${call.method} is not supported');
    }
    _changes.add(uuid);
    return null;
  }
}

// ---------------------------------------------------------------- alarms

/// `browser.alarms`.
class AlarmsApi extends ApiNamespace {
  final Map<String, Map<String, _Alarm>> _alarms = {};

  @override
  String get name => 'alarms';

  @override
  String? get requiredPermission => 'alarms';

  @override
  void detach() {
    for (final alarms in _alarms.values) {
      for (final alarm in alarms.values) {
        alarm.cancel();
      }
    }
    _alarms.clear();
  }

  @override
  Future<void> extensionRemoved(InstalledExtension extension) async {
    for (final alarm in (_alarms.remove(extension.uuid) ?? {}).values) {
      alarm.cancel();
    }
  }

  @override
  Future<Object?> call(ApiCall call) async {
    final alarms = _alarms[call.extension.uuid] ??= {};

    switch (call.method) {
      case 'create':
        // create([name], alarmInfo)
        final first = call.arg(0);
        final name = first is String ? first : '';
        final info = first is String ? call.arg(1) : first;
        if (info is! Map) throw ApiException('alarms.create needs alarm info');
        alarms.remove(name)?.cancel();
        alarms[name] = _start(call, name, info);
        return null;
      case 'get':
        final name = call.arg(0);
        return alarms[name is String ? name : '']?.toJson();
      case 'getAll':
        return [for (final alarm in alarms.values) alarm.toJson()];
      case 'clear':
        final name = call.arg(0);
        final removed = alarms.remove(name is String ? name : '');
        removed?.cancel();
        return removed != null;
      case 'clearAll':
        final had = alarms.isNotEmpty;
        for (final alarm in alarms.values) {
          alarm.cancel();
        }
        alarms.clear();
        return had;
      default:
        throw ApiException('alarms.${call.method} is not supported');
    }
  }

  _Alarm _start(ApiCall call, String name, Map<Object?, Object?> info) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final when = info['when'] is num ? (info['when']! as num).toInt() : null;
    final delay = info['delayInMinutes'] is num
        ? (info['delayInMinutes']! as num).toDouble()
        : null;
    final period = info['periodInMinutes'] is num
        ? (info['periodInMinutes']! as num).toDouble()
        : null;

    final first = when ?? (now + ((delay ?? period ?? 0) * 60000).round());
    final alarm = _Alarm(
      name: name,
      scheduledTime: first,
      periodInMinutes: period,
    );

    final host = call.host;
    final uuid = call.extension.uuid;

    void fire() {
      host.emit(uuid, 'alarms.onAlarm', [alarm.toJson()]);
    }

    final wait = Duration(milliseconds: (first - now).clamp(0, 1 << 31));
    alarm.timer = Timer(wait, () {
      fire();
      if (period != null && period > 0) {
        // Firefox does not allow a period under a minute for installed
        // extensions, and neither does this.
        final interval = Duration(
          milliseconds: (period.clamp(1, double.infinity) * 60000).round(),
        );
        alarm.timer = Timer.periodic(interval, (_) {
          alarm.scheduledTime =
              DateTime.now().millisecondsSinceEpoch + interval.inMilliseconds;
          fire();
        });
      } else {
        _alarms[uuid]?.remove(name);
      }
    });
    return alarm;
  }
}

class _Alarm {
  _Alarm({
    required this.name,
    required this.scheduledTime,
    this.periodInMinutes,
  });

  final String name;
  int scheduledTime;
  final double? periodInMinutes;
  Timer? timer;

  void cancel() => timer?.cancel();

  Map<String, Object?> toJson() => {
    'name': name,
    'scheduledTime': scheduledTime,
    'periodInMinutes': ?periodInMinutes,
  };
}

// ---------------------------------------------------------------- commands

/// `browser.commands`: the keyboard shortcuts in the manifest.
class CommandsApi extends ApiNamespace {
  @override
  String get name => 'commands';

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'getAll':
        final manifest = await call.host.manifestOf(call.extension);
        return [
          for (final command in manifest?.commands ?? const <CommandSpec>[])
            {
              'name': command.name,
              'description': command.description ?? '',
              'shortcut': command.suggestedKey['default'] ?? '',
            },
        ];
      case 'reset':
        return null;
      default:
        throw ApiException('commands.${call.method} is not supported');
    }
  }
}

// ---------------------------------------------------------------- permissions

/// `browser.permissions`, answering from what was granted at install.
class PermissionsApi extends ApiNamespace {
  @override
  String get name => 'permissions';

  @override
  Future<Object?> call(ApiCall call) async {
    final extension = call.extension;

    switch (call.method) {
      case 'getAll':
        return {
          'permissions': extension.grantedPermissions,
          'origins': extension.grantedOrigins,
        };
      case 'contains':
      case 'request':
        // Asking the user is the browser's job and is not built, so a request
        // is granted only when what it asks for was already granted.
        final wanted = call.arg(0);
        if (wanted is! Map) {
          throw ApiException('permissions.${call.method} needs permissions');
        }
        return _contains(extension, wanted);
      case 'remove':
        return false;
      default:
        throw ApiException('permissions.${call.method} is not supported');
    }
  }

  bool _contains(InstalledExtension extension, Map<Object?, Object?> wanted) {
    final permissions = _strings(wanted['permissions']);
    final origins = _strings(wanted['origins']);
    final granted = extension.grantedOrigins
        .map(MatchPattern.tryParse)
        .nonNulls
        .toList();

    return permissions.every(extension.grantedPermissions.contains) &&
        origins.every((origin) {
          final pattern = MatchPattern.tryParse(origin);
          return pattern != null &&
              granted.any((grant) => grant.covers(pattern));
        });
  }

  List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}

// ---------------------------------------------------------------- dns

/// `browser.dns`.
class DnsApi extends ApiNamespace {
  @override
  String get name => 'dns';

  @override
  String? get requiredPermission => 'dns';

  @override
  Future<Object?> call(ApiCall call) async {
    if (call.method != 'resolve') {
      throw ApiException('dns.${call.method} is not supported');
    }

    final hostname = call.arg(0);
    if (hostname is! String || hostname.isEmpty) {
      throw ApiException('dns.resolve needs a host name');
    }

    try {
      final addresses = await InternetAddress.lookup(
        hostname,
      ).timeout(const Duration(seconds: 5));
      return {
        'addresses': [for (final address in addresses) address.address],
        'isTRR': false,
      };
    } on SocketException {
      throw ApiException('NS_ERROR_UNKNOWN_HOST');
    } on TimeoutException {
      throw ApiException('NS_ERROR_NET_TIMEOUT');
    }
  }
}

// ---------------------------------------------------------------- contentScripts

/// A content script an extension registered while running, which lasts until it
/// unregisters it or the browser closes.
class DynamicContentScript {
  const DynamicContentScript(this.id, this.options);

  final String id;
  final Map<String, Object?> options;
}

/// `browser.contentScripts`: scripts registered at run time, which the
/// browser adds to what the web content processes run.
class ContentScriptsApi extends ApiNamespace {
  final Map<String, Map<String, DynamicContentScript>> _scripts = {};
  int _nextId = 1;

  @override
  String get name => 'contentScripts';

  /// The scripts [uuid] has registered.
  Iterable<DynamicContentScript> scriptsFor(String uuid) => [
    ...?_scripts[uuid]?.values,
  ];

  @override
  Future<void> extensionRemoved(InstalledExtension extension) async {
    _scripts.remove(extension.uuid);
  }

  @override
  Future<Object?> call(ApiCall call) async {
    final uuid = call.extension.uuid;

    switch (call.method) {
      case 'register':
        final options = call.arg(0);
        if (options is! Map || options['matches'] is! List) {
          throw ApiException('contentScripts.register needs "matches"');
        }
        final id = 'dynamic-${_nextId++}';
        (_scripts[uuid] ??= {})[id] = DynamicContentScript(
          id,
          options.cast<String, Object?>(),
        );
        await call.host.pushState();
        return id;
      case 'unregister':
        final id = call.arg(0);
        if (_scripts[uuid]?.remove(id) != null) await call.host.pushState();
        return null;
      default:
        throw ApiException('contentScripts.${call.method} is not supported');
    }
  }
}
