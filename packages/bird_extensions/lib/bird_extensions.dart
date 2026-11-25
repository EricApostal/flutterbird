/// WebExtensions support for FlutterBird.
///
/// This package is the part of extension support that does not need the
/// engine: installing from addons.mozilla.org, reading manifests, working out
/// what to ask the user, and keeping track of what is installed.
library;

export 'src/amo_client.dart';
export 'src/engine_state.dart';
export 'src/extension_installer.dart';
export 'src/extension_registry.dart';
export 'src/host/action_api.dart';
export 'src/host/api.dart';
export 'src/host/browser_bridge.dart';
export 'src/host/event_registry.dart';
export 'src/host/extension_host.dart';
export 'src/host/extension_transport.dart';
export 'src/host/misc_apis.dart';
export 'src/host/native_messaging_api.dart';
export 'src/host/port_hub.dart';
export 'src/host/runtime_api.dart';
export 'src/host/storage_api.dart';
export 'src/host/system_apis.dart';
export 'src/host/tabs_api.dart';
export 'src/host/web_navigation_api.dart';
export 'src/host/web_request_api.dart';
export 'src/host/windows_api.dart';
export 'src/http_fetcher.dart';
export 'src/localization.dart';
export 'src/manifest.dart';
export 'src/match_pattern.dart';
export 'src/permissions.dart';
export 'src/shim/shim_source.dart';
export 'src/version.dart';
export 'src/xpi_extractor.dart';
export 'src/zip_reader.dart';
export 'src/zip_writer.dart';
