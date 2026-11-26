// Settings ABI smoke check: drives the settings parts of libengine's C ABI
// directly, with no Flutter and no window, to check that the settings the app
// writes reach the engine and come back as the engine stores them.
//
// The ABI is positional, and a name the engine does not recognize fails
// silently rather than loudly, so a renamed setting would leave the settings
// page writing into nothing. Run this after changing engine.h's settings
// functions or the JSON keys the page uses:
//
//   flutter build macos --debug
//   APP=build/macos/Build/Products/Debug/Rubisco Browser.app
//   mkdir -p /tmp/libbird-home && ln -sfn "$PWD/packages/libbird/third_party/ladybird/Base/res" /tmp/libbird-home/.lagom
//   # The helpers are found next to the executable that starts the engine, so
//   # the harness runs from where the app's helpers are, and the engine is a
//   # relative path from there.
//   dart compile exe packages/libbird/tool/settings_abi_smoke.dart -o "$APP/Contents/MacOS/settings_abi_smoke"
//   (cd "$APP/Contents/MacOS" && HOME=/tmp/libbird-home ./settings_abi_smoke \
//       ../Resources/libengine.dylib)
//
// It exits non-zero if any check fails.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';

int failures = 0;

void check(String what, bool ok) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $what');
  if (!ok) failures++;
}

String? settingsJson(LadybirdBindings b) {
  final ptr = b.get_settings_json();
  if (ptr == ffi.nullptr) return null;
  final json = ptr.cast<Utf8>().toDartString();
  malloc.free(ptr);
  return json;
}

bool apply(LadybirdBindings b, String json) {
  final ptr = json.toNativeUtf8();
  final result = b.apply_settings_json(ptr.cast<ffi.Char>());
  malloc.free(ptr);
  return result;
}

bool removeEngine(LadybirdBindings b, String name) {
  final ptr = name.toNativeUtf8();
  final result = b.remove_custom_search_engine(ptr.cast<ffi.Char>());
  malloc.free(ptr);
  return result;
}

bool addEngine(LadybirdBindings b, String name, String url) {
  final n = name.toNativeUtf8();
  final u = url.toNativeUtf8();
  final result = b.add_custom_search_engine(n.cast<ffi.Char>(), u.cast<ffi.Char>());
  malloc.free(n);
  malloc.free(u);
  return result;
}

List<String> engineNames(LadybirdBindings b) {
  final ptr = b.get_search_engines_json();
  if (ptr == ffi.nullptr) return const [];
  final json = ptr.cast<Utf8>().toDartString();
  malloc.free(ptr);
  return [
    for (final engine in jsonDecode(json) as List)
      (engine as Map)['name'] as String,
  ];
}

void main(List<String> args) {
  final lib = ffi.DynamicLibrary.open(args[0]);
  final b = LadybirdBindings(lib);
  b.init_ladybird();
  final view = b.create_web_view();
  for (var i = 0; i < 200; i++) {
    b.tick_ladybird();
  }
  stdout.writeln('view: $view');

  final before = settingsJson(b);
  check('settings snapshot', before != null && before.contains('appearance'));

  check('refuses non-object', !apply(b, '[]'));
  check('refuses invalid json', !apply(b, 'not json'));

  check('sets a nested appearance value', apply(b, '{"appearance":{"interfaceTheme":"light"}}'));
  var settings = jsonDecode(settingsJson(b)!) as Map;
  check('interface theme is light', settings['appearance']['interfaceTheme'] == 'light');
  check('a key it did not name is untouched',
      settings['newTabPageURL'] == (jsonDecode(before!) as Map)['newTabPageURL']);

  check('sets a config variable through the snapshot',
      apply(b, '{"configVariables":{"downloads.maximum_connections_per_download":2}}'));
  settings = jsonDecode(settingsJson(b)!) as Map;
  check('config variable applied',
      settings['configVariables']['downloads.maximum_connections_per_download'] == 2);

  check('restores the appearance', apply(b, '{"appearance":{"interfaceTheme":"system"}}'));

  check('adds a custom engine', addEngine(b, 'Smoke Engine', 'https://example.com/?q=%s'));
  check('engine is listed', engineNames(b).contains('Smoke Engine'));
  check('removes it', removeEngine(b, 'Smoke Engine'));
  check('engine is gone', !engineNames(b).contains('Smoke Engine'));
  check('removing it again fails', !removeEngine(b, 'Smoke Engine'));
  check('cannot remove a builtin', !removeEngine(b, 'DuckDuckGo'));
  check('builtin still there', engineNames(b).contains('DuckDuckGo'));

  stdout.writeln(failures == 0 ? 'all checks passed' : '$failures check(s) failed');
  exit(failures == 0 ? 0 : 1);
}
