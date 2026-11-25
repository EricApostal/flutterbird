import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';

import '../providers/browser.dart';
import 'engine_transport.dart';

/// Everything the app does with extensions: what is installed, installing,
/// updating and removing, and running them in the engine.
///
/// It is built once the engine is up, since the engine's own profile
/// directory is where extensions are kept, and lives as long as the app.
class ExtensionService {
  ExtensionService._({
    required this.registry,
    required this.installer,
    required this.host,
    required this.actions,
    required this.menus,
    required this.webRequest,
    required ExtensionEngineBridge bridge,
    required IoHttpFetcher fetcher,
    required List<StreamSubscription<Object?>> subscriptions,
    required IOSink traceFile,
  }) : _traceFile = traceFile,
       _bridge = bridge,
       _fetcher = fetcher,
       _subscriptions = subscriptions;

  final IOSink _traceFile;
  final ExtensionRegistry registry;
  final ExtensionInstaller installer;
  final ExtensionHost host;

  /// The toolbar buttons of the extensions, for the app to draw.
  final ActionStore actions;

  /// The context menu items the extensions made.
  final MenusApi menus;

  /// What the network layer asks to apply extensions' request rules.
  final WebRequestApi webRequest;

  final ExtensionEngineBridge _bridge;
  final IoHttpFetcher _fetcher;
  final List<StreamSubscription<Object?>> _subscriptions;

  /// Opens the extensions in [profileDirectory], gives the engine what it
  /// needs to run them, and starts answering their API calls.
  static Future<ExtensionService> start({
    required String profileDirectory,
    BrowserBridge? browser,
    ExtensionEngineBridge? bridge,
  }) async {
    final engine = bridge ?? ExtensionEngineBridge.instance;
    final root = Directory('$profileDirectory/extensions');

    final registry = await ExtensionRegistry.open(root);
    final fetcher = IoHttpFetcher(userAgent: 'FlutterBird');
    final installer = ExtensionInstaller(
      registry: registry,
      amo: AmoClient(fetcher),
    );

    final actions = ActionStore();
    final menus = MenusApi();
    final webRequest = WebRequestApi();
    final contentScripts = ContentScriptsApi();

    // Temporary, while extensions are being made to work: the trace of the
    // latest run is also kept in a file, whole, where console output is not.
    final traceFile = File('${root.path}/trace.log').openWrite();

    final host = ExtensionHost(
      registry: registry,
      transport: EngineExtensionTransport(engine),
      browser: browser,
      trace: (line) {
        debugPrint(line);
        traceFile.writeln('${DateTime.now().toIso8601String()} $line');
      },
      stateBuilder: EngineStateBuilder(
        registry: registry,
        platform: _platform,
        dynamicScripts: contentScripts.scriptsFor,
        // Requests are only held for extensions when one wants to block.
        interceptRequests: () =>
            webRequest.wantsToBlock('webRequest.onBeforeRequest') ||
            webRequest.wantsToBlock('webRequest.onBeforeSendHeaders'),
      ),
      apis: [
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
      ],
    );

    // A button appears for each extension that has one, and goes with it.
    Future<void> describe(InstalledExtension extension) async {
      final manifest = await host.manifestOf(extension);
      if (manifest?.action != null && extension.enabled) {
        actions.setDefaults(extension, manifest!);
      } else {
        actions.remove(extension);
      }
    }

    final subscription = registry.changes.listen((change) {
      if (change.kind == RegistryChangeKind.removed) {
        actions.remove(change.extension);
      } else {
        unawaited(describe(change.extension));
      }
    });
    for (final extension in registry.extensions) {
      await describe(extension);
    }

    // The host subscribes before the engine is told to call back, so that
    // nothing the engine reports is missed.
    await host.start();
    engine.start();

    // When an extension starts or stops wanting to block requests, the web
    // content processes need telling, so that they hold requests or stop.
    final interest = webRequest.interestChanged.listen((_) {
      unawaited(host.pushState());
    });

    // A request a process holds for the extensions is answered by asking them.
    // One that gets no answer in time goes ahead, rather than hanging the page.
    final intercepts = engine.interceptRequests.listen((request) async {
      var verdict = '{}';
      try {
        final details = (jsonDecode(request.detailsJson) as Map)
            .cast<String, Object?>();
        details['tabId'] = request.viewId ?? -1;
        verdict = await webRequest.intercept(details);
      } on Object {
        verdict = '{}';
      }
      engine.respondToIntercept(request.requestId, verdict);
    });
    engine.startIntercepting();

    return ExtensionService._(
      traceFile: traceFile,
      registry: registry,
      installer: installer,
      host: host,
      actions: actions,
      menus: menus,
      webRequest: webRequest,
      bridge: engine,
      fetcher: fetcher,
      subscriptions: [subscription, interest, intercepts],
    );
  }

  static String get _platform {
    if (Platform.isMacOS) return 'mac';
    if (Platform.isWindows) return 'win';
    if (Platform.isAndroid) return 'android';
    return 'linux';
  }

  List<InstalledExtension> get extensions => registry.extensions;

  Future<InstallResult> installFromAmo(
    String input, {
    required InstallPromptHandler onPrompt,
    void Function(int received, int? total)? onProgress,
  }) => installer.installFromAmo(
    input,
    onPrompt: onPrompt,
    onProgress: onProgress,
  );

  /// Installs an unpacked extension folder, for developing one.
  Future<InstallResult> loadUnpacked(
    String path, {
    required InstallPromptHandler onPrompt,
  }) => installer.installFromDirectory(Directory(path), onPrompt: onPrompt);

  Future<void> uninstall(String id) => installer.uninstall(id);

  Future<void> setEnabled(String id, {required bool enabled}) =>
      registry.setEnabled(id, enabled: enabled);

  /// Updates every AMO extension that has a newer version. Returns how many
  /// were updated. Updates that ask for more than the old version did wait
  /// for [onPrompt]; one it declines is skipped.
  Future<int> updateAll({required InstallPromptHandler onPrompt}) async {
    var updated = 0;
    for (final extension in registry.extensions) {
      if (!extension.source.isAmo) continue;
      try {
        if (await installer.update(extension.id, onPrompt: onPrompt) != null) {
          updated++;
        }
      } on InstallCancelled {
        continue;
      }
    }
    return updated;
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _bridge.stop();
    await host.dispose();
    await _traceFile.close();
    await registry.dispose();
    _fetcher.close();
  }
}

/// How the app gives extensions its tabs, and where it runs their background
/// pages. The app overrides this; without it extensions run with no browser
/// around them and most of their API is unavailable.
final browserBridgeProvider = Provider<BrowserBridge?>((ref) => null);

/// The extensions of this app, once the engine is up.
final extensionServiceProvider = FutureProvider<ExtensionService>((ref) async {
  // The first tab's controller is what starts the engine, and it knows the
  // profile directory. It is read, not watched: opening a tab must not
  // restart the extensions.
  final controller = ref.read(browserTabControllerProvider).first;
  final directory = controller.getProfileConfigDirectory();
  if (directory == null) {
    throw StateError('The engine has no profile directory for extensions');
  }

  final service = await ExtensionService.start(
    profileDirectory: directory,
    browser: ref.read(browserBridgeProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// What is installed, kept current as it changes.
final installedExtensionsProvider = StreamProvider<List<InstalledExtension>>((
  ref,
) async* {
  final service = await ref.watch(extensionServiceProvider.future);
  yield service.extensions;
  await for (final _ in service.registry.changes) {
    yield service.extensions;
  }
});

/// The extensions that have a toolbar button, kept current as buttons change.
final extensionActionsProvider = StreamProvider<List<InstalledExtension>>((
  ref,
) async* {
  final service = await ref.watch(extensionServiceProvider.future);

  List<InstalledExtension> current() => [
    for (final uuid in service.actions.uuids) ?service.registry.byUuid(uuid),
  ];

  yield current();
  await for (final _ in service.actions.changes) {
    yield current();
  }
});
