/// APIs about the computer and the browser around an extension. An extension
/// commonly adds listeners to these while it starts, so one that is missing
/// stops its background page partway through.
library;

import 'dart:async';

import '../extension_registry.dart';
import 'api.dart';

// ---------------------------------------------------------------- idle

/// `browser.idle`. How long the user has been away is not measured, so the
/// user is always reported as active and `onStateChanged` never fires.
class IdleApi extends ApiNamespace {
  @override
  String get name => 'idle';

  @override
  String? get requiredPermission => 'idle';

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'queryState':
        return 'active';
      case 'setDetectionInterval':
        return null;
      default:
        throw ApiException('idle.${call.method} is not supported');
    }
  }
}

// ---------------------------------------------------------------- notifications

/// A notification an extension has up.
class ExtensionNotification {
  const ExtensionNotification(this.extensionUuid, this.id, this.options);

  final String extensionUuid;
  final String id;
  final Map<String, Object?> options;
}

/// `browser.notifications`. They are kept, and offered to the app on [shown];
/// showing one on the desktop is the app's job and is not built.
class NotificationsApi extends ApiNamespace {
  final Map<String, Map<String, ExtensionNotification>> _notifications = {};
  final StreamController<ExtensionNotification> _shown =
      StreamController<ExtensionNotification>.broadcast();
  int _nextId = 1;

  Stream<ExtensionNotification> get shown => _shown.stream;

  @override
  String get name => 'notifications';

  @override
  String? get requiredPermission => 'notifications';

  @override
  Future<void> extensionRemoved(InstalledExtension extension) async {
    _notifications.remove(extension.uuid);
  }

  @override
  Future<Object?> call(ApiCall call) async {
    final uuid = call.extension.uuid;
    final mine = _notifications[uuid] ??= {};

    switch (call.method) {
      case 'create':
        final given = call.arg(0);
        final options = call.arg(1);
        if (options is! Map) {
          throw ApiException('notifications.create needs options');
        }
        final id = given is String && given.isNotEmpty
            ? given
            : 'notification-${_nextId++}';
        final notification = ExtensionNotification(
          uuid,
          id,
          options.cast<String, Object?>(),
        );
        mine[id] = notification;
        _shown.add(notification);
        return id;
      case 'update':
        final id = call.arg(0);
        final options = call.arg(1);
        final existing = mine[id];
        if (existing == null || options is! Map) return false;
        existing.options.addAll(options.cast<String, Object?>());
        return true;
      case 'clear':
        return mine.remove(call.arg(0)) != null;
      case 'getAll':
        return {for (final entry in mine.entries) entry.key: entry.value.options};
      default:
        throw ApiException('notifications.${call.method} is not supported');
    }
  }
}

// ---------------------------------------------------------------- management

/// `browser.management`: what extensions there are. As in Firefox, an
/// extension may always ask about itself, and needs the `management`
/// permission to ask about the others.
class ManagementApi extends ApiNamespace {
  @override
  String get name => 'management';

  static Map<String, Object?> _info(InstalledExtension extension) => {
    'id': extension.id,
    'name': extension.name,
    'version': extension.version,
    'enabled': extension.enabled,
    'type': 'extension',
    'installType': 'normal',
    'mayDisable': true,
    'permissions': extension.grantedPermissions,
    'hostPermissions': extension.grantedOrigins,
  };

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'getSelf':
        return _info(call.extension);
      case 'getAll':
        if (!call.extension.grantedPermissions.contains('management')) {
          throw ApiException(
            'The "management" permission is required to see other extensions',
          );
        }
        return [
          for (final extension in call.host.registry.extensions)
            _info(extension),
        ];
      case 'setEnabled':
        // Firefox lets this change only themes.
        throw ApiException('Extensions cannot enable or disable extensions');
      default:
        throw ApiException('management.${call.method} is not supported');
    }
  }
}

// ---------------------------------------------------------------- downloads

/// `browser.downloads`, which is there so that listening to it works. Starting
/// a download is not built, and says so.
class DownloadsApi extends ApiNamespace {
  @override
  String get name => 'downloads';

  @override
  String? get requiredPermission => 'downloads';

  @override
  Future<Object?> call(ApiCall call) async =>
      throw ApiException('downloads.${call.method} is not supported yet');
}
