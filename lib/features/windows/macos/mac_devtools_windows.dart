// See mac_window_system.dart about the experimental API.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';

import 'package:bird_devtools/bird_devtools.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_macos.dart';
import 'package:bird_window/bird_window.dart';

/// The window one tab's developer tools are in, when they are not docked.
class MacDevToolsWindow {
  MacDevToolsWindow._(this.tabId, this.controller, this.native);

  final int tabId;
  final WindowController controller;
  final MacWindow native;
}

/// The toolboxes that have windows of their own ("Separate Window").
class MacDevToolsWindows extends ChangeNotifier {
  MacDevToolsWindows(this.manager) {
    manager
      ..supportsSeparateWindow = true
      ..onWindowedChanged = _setWindowed;
  }

  final DevToolsManager manager;
  final Map<int, MacDevToolsWindow> _windows = {};

  List<MacDevToolsWindow> get windows => List.unmodifiable(_windows.values);

  // The manager says this while it is changing, perhaps while widgets are being
  // built, so the windows follow a moment later.
  void _setWindowed(int tabId, bool open) =>
      scheduleMicrotask(() => open ? _open(tabId) : _close(tabId));

  void _open(int tabId) {
    final existing = _windows[tabId];
    if (existing != null) {
      if (existing.native.isVisible) existing.native.makeKeyAndOrderFront();
      return;
    }
    final screen =
        MacDesktop.screens().firstOrNull?.visibleFrame ??
        const ScreenRect(0, 0, 1440, 900);
    final width = (screen.width * 0.6).clamp(700.0, 1100.0);
    final height = (screen.height * 0.6).clamp(450.0, 700.0);
    final controller = WindowController(
      size: Size(width, height),
      constraints: const BoxConstraints(minWidth: 420, minHeight: 300),
      title: 'Developer Tools',
      delegate: _DevToolsWindowDelegate(manager, tabId),
    );
    final native = MacWindow(
      (controller as WindowControllerMacOS).windowHandle,
    );
    // Down and to the right of the middle, clear of most of the page.
    native.frame = ScreenRect(
      screen.left + (screen.width - width) / 2 + 60,
      screen.top + (screen.height - height) / 2 + 60,
      width,
      height,
    );
    _windows[tabId] = MacDevToolsWindow._(tabId, controller, native);
    notifyListeners();
    WidgetsBinding.instance.scheduleFrame();
  }

  void _close(int tabId) {
    final window = _windows.remove(tabId);
    if (window == null) return;
    if (!window.controller.isDestroyed) window.native.orderOut();
    notifyListeners();
    WidgetsBinding.instance.scheduleFrame();
    // As with browser windows: destroyed once Flutter has stopped drawing into
    // it, and not from inside a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(milliseconds: 150), () {
        window.controller.destroy();
        window.controller.dispose();
      });
    });
  }
}

class _DevToolsWindowDelegate with WindowControllerDelegate {
  _DevToolsWindowDelegate(this._manager, this._tabId);

  final DevToolsManager _manager;
  final int _tabId;

  // Closing the window closes the tools; the manager then retires the window.
  @override
  void onWindowCloseRequested(WindowController controller) =>
      _manager.close(_tabId);
}
