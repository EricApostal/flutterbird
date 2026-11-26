import 'dart:convert';
import 'dart:io';

import '../engine_state.dart';
import '../extension_registry.dart';
import 'action_api.dart';
import 'api.dart';
import 'misc_apis.dart';
import 'native_messaging_api.dart';
import 'storage_api.dart';
import 'system_apis.dart';
import 'tabs_api.dart';
import 'web_navigation_api.dart';
import 'web_request_api.dart';
import 'windows_api.dart';

/// The parts of a running extension host that its embedder also talks to.
///
/// The app and the end-to-end tests both build their host from this, so that
/// what is tested is what runs.
class ExtensionRuntimeParts {
  /// [root] is the directory extensions are kept in.
  ExtensionRuntimeParts({required this.root, required this.registry});

  final Directory root;
  final ExtensionRegistry registry;

  final ActionStore actions = ActionStore();
  final MenusApi menus = MenusApi();
  final WebRequestApi webRequest = WebRequestApi();
  final ContentScriptsApi contentScripts = ContentScriptsApi();

  /// Every API there is, apart from `runtime`, which the host adds itself.
  late final List<ApiNamespace> apis = [
    StorageApi(Directory('${root.path}/storage')),
    TabsApi(),
    WindowsApi(),
    WebNavigationApi(),
    ActionApi('browserAction', actions),
    ActionApi('action', actions),
    menus,
    AlarmsApi(),
    CommandsApi(),
    PermissionsApi(),
    DnsApi(),
    NativeMessagingApi(),
    IdleApi(),
    NotificationsApi(),
    ManagementApi(),
    DownloadsApi(),
    ScriptingApi(),
    contentScripts,
    webRequest,
  ];

  EngineStateBuilder stateBuilder(String platform) => EngineStateBuilder(
    registry: registry,
    platform: platform,
    dynamicScripts: contentScripts.scriptsFor,
    // Requests are only held for extensions when one wants to block.
    interceptRequests: () => wantsToIntercept,
    interceptResponses: () =>
        webRequest.wantsToBlock('webRequest.onHeadersReceived'),
  );

  bool get wantsToIntercept =>
      webRequest.wantsToBlock('webRequest.onBeforeRequest') ||
      webRequest.wantsToBlock('webRequest.onBeforeSendHeaders');

  /// What the extensions want done with a request the engine is holding.
  /// [viewId] is the tab it is for, if the engine knows. A failure lets the
  /// request go ahead rather than leaving the page hanging.
  Future<String> intercept(String detailsJson, int? viewId) async {
    try {
      final details = (jsonDecode(detailsJson) as Map).cast<String, Object?>();
      details['tabId'] = viewId ?? -1;
      return await webRequest.intercept(details);
    } on Object {
      return '{}';
    }
  }
}
