import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bird_devtools/bird_devtools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';
import 'package:rubisco_browser/features/windows/window_system.dart';

/// The developer tools are a desktop tool: a phone has no room for them.
bool get devToolsSupported =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;

/// What the tools need from this browser.
class BrowserDevToolsHost implements DevToolsHost {
  BrowserDevToolsHost(this._ref);

  final Ref _ref;

  @override
  Future<int> startServer() async => LadybirdDevTools.instance.startServer();

  @override
  void stopServer() => LadybirdDevTools.instance.stopServer();

  // A tab is its engine view.
  @override
  int? browserIdFor(int tabId) => LadybirdDevTools.instance.browserIdFor(tabId);

  @override
  void openLink(String url, {required int fromTab}) {
    final shell = _ref.read(browserShellProvider);
    shell.openTab(windowId: shell.session.windowOfTab(fromTab)?.id, url: url);
  }

  @override
  Future<String?> saveFile(String suggestedName, List<int> bytes) async {
    try {
      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      // Never writes over a file that is already there.
      final name = path.basename(suggestedName);
      final stem = path.basenameWithoutExtension(name);
      final extension = path.extension(name);
      var file = File(path.join(directory.path, name));
      for (var number = 1; await file.exists(); number++) {
        file = File(path.join(directory.path, '$stem ($number)$extension'));
      }
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (error) {
      debugPrint('Could not save $suggestedName: $error');
      return null;
    }
  }
}

Future<File> _settingsFile() async {
  final directory = await getApplicationSupportDirectory();
  return File(path.join(directory.path, 'devtools.json'));
}

Future<void> _loadSettings(DevToolsSettings settings) async {
  try {
    final file = await _settingsFile();
    if (!await file.exists()) return;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, Object?>) settings.load(decoded);
  } catch (error) {
    debugPrint('Could not load the developer tools settings: $error');
  }
}

Future<void> _saveSettings(Map<String, Object?> values) async {
  try {
    final file = await _settingsFile();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(values), flush: true);
    await temporary.rename(file.path);
  } catch (error) {
    debugPrint('Could not save the developer tools settings: $error');
  }
}

/// The developer tools of every tab, or null where there are none.
final devToolsProvider = Provider<DevToolsManager?>((ref) {
  if (!devToolsSupported) return null;

  final manager = DevToolsManager(BrowserDevToolsHost(ref));
  manager.settings.onSave = (values) => unawaited(_saveSettings(values));
  unawaited(_loadSettings(manager.settings));

  final engine = LadybirdDevTools.instance;
  engine.onInspectRequested = (viewId, x, y) {
    // A view that is no tab, such as an extension's popup, has no tools.
    if (ref.read(browserShellProvider).session.windowOfTab(viewId) == null) {
      return;
    }
    unawaited(
      manager.inspectElement(viewId, () => engine.inspectElement(viewId, x, y)),
    );
  };
  engine.listenForInspectRequests();

  ref.onDispose(manager.shutDown);
  return manager;
});

/// Whether the keyboard is in the developer tools of [tabId], so that the
/// browser leaves the tools' own shortcuts to them.
bool devToolsHasFocus(WidgetRef ref, int tabId) =>
    ref.read(devToolsProvider)?.stateOf(tabId)?.focus.hasFocus ?? false;

enum _DevToolsCommand { toggle, tool, picker, responsive }

(_DevToolsCommand, String)? _commandFor(KeyDownEvent event) {
  final keyboard = HardwareKeyboard.instance;
  final shift = keyboard.isShiftPressed;
  final alt = keyboard.isAltPressed;
  final primary = Platform.isMacOS
      ? keyboard.isMetaPressed
      : keyboard.isControlPressed;

  // Option changes what a key types, so the key's place is looked at too.
  bool pressed(LogicalKeyboardKey logical, PhysicalKeyboardKey physical) =>
      event.logicalKey == logical || event.physicalKey == physical;

  if (!primary && !alt) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f12) {
      return shift
          ? (_DevToolsCommand.tool, 'accessibility')
          : (_DevToolsCommand.toggle, '');
    }
    if (!shift) return null;
    if (key == LogicalKeyboardKey.f7) {
      return (_DevToolsCommand.tool, 'styleeditor');
    }
    if (key == LogicalKeyboardKey.f9) return (_DevToolsCommand.tool, 'storage');
    if (key == LogicalKeyboardKey.f5) {
      return (_DevToolsCommand.tool, 'performance');
    }
    return null;
  }

  // Firefox's chords: Command-Option on a Mac, Control-Shift elsewhere.
  final chord = Platform.isMacOS
      ? primary && alt && !shift
      : primary && shift && !alt;
  if (primary &&
      shift &&
      !alt &&
      pressed(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC)) {
    return (_DevToolsCommand.picker, '');
  }
  if (!chord) return null;
  if (pressed(LogicalKeyboardKey.keyI, PhysicalKeyboardKey.keyI)) {
    return (_DevToolsCommand.toggle, '');
  }
  if (pressed(LogicalKeyboardKey.keyK, PhysicalKeyboardKey.keyK)) {
    return (_DevToolsCommand.tool, 'console');
  }
  if (pressed(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC)) {
    return (_DevToolsCommand.picker, '');
  }
  if (pressed(LogicalKeyboardKey.keyZ, PhysicalKeyboardKey.keyZ)) {
    return (_DevToolsCommand.tool, 'debugger');
  }
  if (pressed(LogicalKeyboardKey.keyE, PhysicalKeyboardKey.keyE)) {
    return (_DevToolsCommand.tool, 'network');
  }
  if (pressed(LogicalKeyboardKey.keyM, PhysicalKeyboardKey.keyM)) {
    return (_DevToolsCommand.responsive, '');
  }
  return null;
}

/// Acts on a developer tools shortcut for the tab a window is showing. Returns
/// whether the key was one.
bool handleDevToolsShortcut(
  WidgetRef ref,
  KeyEvent event, {
  required int windowId,
  required int tabId,
}) {
  if (event is! KeyDownEvent) return false;
  final manager = ref.read(devToolsProvider);
  if (manager == null) return false;
  final command = _commandFor(event);
  if (command == null) return false;
  // Every window's handler hears the key.
  if (!ref.read(windowSystemProvider).claimShortcut(windowId, event)) {
    return false;
  }
  switch (command) {
    case (_DevToolsCommand.toggle, _):
      manager.toggle(tabId);
    case (_DevToolsCommand.tool, final tool):
      manager.toggleTool(tabId, tool);
    case (_DevToolsCommand.picker, _):
      unawaited(manager.togglePicker(tabId));
    case (_DevToolsCommand.responsive, _):
      manager.toggleResponsive(tabId);
  }
  return true;
}
