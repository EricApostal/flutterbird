import 'dart:async';

import '../extension_registry.dart';
import '../manifest.dart';
import 'api.dart';
import 'extension_host.dart';

/// What one extension's toolbar button looks like, for one tab or for all.
class ActionState {
  ActionState({
    this.title,
    this.popup,
    this.badgeText,
    this.badgeBackground,
    this.badgeTextColor,
    this.enabled,
    this.iconPath,
  });

  String? title;
  String? popup;
  String? badgeText;
  List<int>? badgeBackground;
  List<int>? badgeTextColor;
  bool? enabled;
  String? iconPath;
}

/// The toolbar buttons of all extensions. The app draws them from here and
/// is told when one changes; extensions change them through `browserAction`
/// and `action`.
class ActionStore {
  final Map<String, ActionState> _global = {};
  final Map<String, Map<int, ActionState>> _perTab = {};
  final Map<String, ActionState> _defaults = {};
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// The uuid of an extension whose button changed.
  Stream<String> get changes => _changes.stream;

  final StreamController<String> _popupRequests =
      StreamController<String>.broadcast();

  /// The uuid of an extension that asked for its popup to open, as
  /// `browserAction.openPopup` does.
  Stream<String> get popupRequests => _popupRequests.stream;

  void requestPopup(String uuid) => _popupRequests.add(uuid);

  /// Sets the manifest's own values, which show until an extension changes them.
  void setDefaults(InstalledExtension extension, Manifest manifest) {
    final spec = manifest.action;
    _defaults[extension.uuid] = ActionState(
      title: spec?.defaultTitle ?? extension.name,
      popup: spec?.defaultPopup,
      badgeText: '',
      enabled: true,
      // An extension whose button names no icon shows the one of the
      // extension itself, as in Firefox. The button is 20 points wide, which
      // is 40 pixels on the screens that most need a sharp one.
      iconPath:
          (spec == null ? null : bestIconPath(spec.defaultIcon, 32)) ??
          bestIconPath(manifest.icons, 32),
    );
    _changes.add(extension.uuid);
  }

  void remove(InstalledExtension extension) {
    _defaults.remove(extension.uuid);
    _global.remove(extension.uuid);
    _perTab.remove(extension.uuid);
    _changes.add(extension.uuid);
  }

  /// The extensions that have a toolbar button, in the order they were set up.
  Iterable<String> get uuids => _defaults.keys.toList();

  /// What the button shows for [tabId]: a tab's own settings, then the
  /// extension's, then the manifest's.
  ActionState stateFor(String uuid, {int? tabId}) {
    final defaults = _defaults[uuid];
    final global = _global[uuid];
    final tab = tabId == null ? null : _perTab[uuid]?[tabId];

    T? pick<T>(T? Function(ActionState) read) {
      for (final layer in [tab, global, defaults]) {
        final value = layer == null ? null : read(layer);
        if (value != null) return value;
      }
      return null;
    }

    return ActionState(
      title: pick((s) => s.title),
      popup: pick((s) => s.popup),
      badgeText: pick((s) => s.badgeText),
      badgeBackground: pick((s) => s.badgeBackground),
      badgeTextColor: pick((s) => s.badgeTextColor),
      enabled: pick((s) => s.enabled),
      iconPath: pick((s) => s.iconPath),
    );
  }

  void update(String uuid, int? tabId, void Function(ActionState) change) {
    final target = tabId == null
        ? (_global[uuid] ??= ActionState())
        : ((_perTab[uuid] ??= {})[tabId] ??= ActionState());
    change(target);
    _changes.add(uuid);
  }

  /// A tab closed: what was set for it goes.
  void forgetTab(int tabId) {
    for (final tabs in _perTab.values) {
      tabs.remove(tabId);
    }
  }
}

/// `browser.browserAction` and `browser.action`: the extension's toolbar button.
class ActionApi extends ApiNamespace {
  ActionApi(this.name, this.store);

  @override
  final String name;

  final ActionStore store;

  @override
  Future<void> extensionRemoved(InstalledExtension extension) async =>
      store.remove(extension);

  @override
  Future<Object?> call(ApiCall call) async {
    final details = call.arg(0);
    final map = details is Map ? details : const {};
    final tabId = map['tabId'] is int ? map['tabId'] as int : null;
    final uuid = call.extension.uuid;

    switch (call.method) {
      case 'setTitle':
        store.update(uuid, tabId, (s) => s.title = map['title'] as String?);
        return null;
      case 'getTitle':
        return store.stateFor(uuid, tabId: tabId).title ?? '';
      case 'setPopup':
        store.update(
          uuid,
          tabId,
          (s) => s.popup = (map['popup'] as String?) ?? '',
        );
        return null;
      case 'getPopup':
        return store.stateFor(uuid, tabId: tabId).popup ?? '';
      case 'setBadgeText':
        store.update(
          uuid,
          tabId,
          (s) => s.badgeText = (map['text'] as String?) ?? '',
        );
        return null;
      case 'getBadgeText':
        return store.stateFor(uuid, tabId: tabId).badgeText ?? '';
      case 'setBadgeBackgroundColor':
        store.update(
          uuid,
          tabId,
          (s) => s.badgeBackground = _color(map['color']),
        );
        return null;
      case 'getBadgeBackgroundColor':
        return store.stateFor(uuid, tabId: tabId).badgeBackground ??
            const [217, 0, 0, 255];
      case 'setBadgeTextColor':
        store.update(
          uuid,
          tabId,
          (s) => s.badgeTextColor = _color(map['color']),
        );
        return null;
      case 'getBadgeTextColor':
        return store.stateFor(uuid, tabId: tabId).badgeTextColor ??
            const [255, 255, 255, 255];
      case 'enable':
      case 'disable':
        final tab = details is int ? details : null;
        store.update(uuid, tab, (s) => s.enabled = call.method == 'enable');
        return null;
      case 'isEnabled':
        return store.stateFor(uuid, tabId: tabId).enabled ?? true;
      case 'setIcon':
        // A path to an image of the extension. An image given as pixels is
        // not drawn; the button keeps the icon it has.
        final path = _iconPath(map['path']);
        if (path != null) store.update(uuid, tabId, (s) => s.iconPath = path);
        return null;
      case 'getUserSettings':
        // Every extension's button is on the toolbar.
        return {'isOnToolbar': true};
      case 'openPopup':
        store.requestPopup(uuid);
        return null;
      default:
        throw ApiException('$name.${call.method} is not supported');
    }
  }

  static String? _iconPath(Object? value) {
    if (value is String) return normalizeResourcePath(value);
    if (value is Map) {
      final sizes = {
        for (final entry in value.entries)
          if (entry.value is String &&
              normalizeResourcePath(entry.value as String) != null)
            entry.key.toString(): normalizeResourcePath(entry.value as String)!,
      };
      return bestIconPath(sizes, 32);
    }
    return null;
  }

  /// A color as `[r, g, b, a]`, from the forms `browser.action` accepts.
  static List<int>? _color(Object? value) {
    if (value is List && value.length >= 3 && value.every((v) => v is num)) {
      return [
        for (final component in value.take(4))
          (component as num).round().clamp(0, 255),
        if (value.length == 3) 255,
      ];
    }
    if (value is String) {
      final hex = value.startsWith('#') ? value.substring(1) : null;
      if (hex != null && (hex.length == 6 || hex.length == 8)) {
        final number = int.tryParse(hex, radix: 16);
        if (number != null) {
          final padded = hex.length == 6 ? (number << 8) | 0xFF : number;
          return [
            (padded >> 24) & 0xFF,
            (padded >> 16) & 0xFF,
            (padded >> 8) & 0xFF,
            padded & 0xFF,
          ];
        }
      }
    }
    return null;
  }

  /// Tells an extension its button was pressed, which is what happens when it
  /// has no popup to show.
  static void notifyClicked(
    ExtensionHost host,
    InstalledExtension extension,
    Map<String, Object?> tab,
  ) {
    host.emit(extension.uuid, 'browserAction.onClicked', [tab]);
    host.emit(extension.uuid, 'action.onClicked', [tab]);
  }
}
