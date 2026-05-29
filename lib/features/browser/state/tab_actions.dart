// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart' show MaterialPageRoute, Navigator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutterbird/features/browser/screens/detached_tab_window.dart';
import 'package:flutterbird/features/browser/state/detached_browser_window_session.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_toolbox/src/custom_window.dart' as custom_window;
import 'package:window_toolbox/window_toolbox.dart';

class BrowserTabActions {
  static final Set<int> _tabsBeingDetached = <int>{};
  static final Map<DetachedBrowserWindowSession, _DetachedTabWindowSession>
  _detachedSessions =
      <DetachedBrowserWindowSession, _DetachedTabWindowSession>{};

  static LadybirdController openNewTab(WidgetRef ref, BuildContext context) {
    final controller = ref.read(browserTabControllerProvider.notifier).add();
    context.go('/browser/tab/${controller.viewId}');
    return controller;
  }

  static Future<bool> detachTabToNewWindow(
    WidgetRef ref,
    BuildContext context, {
    required int currentViewId,
    required int detachViewId,
    Offset? initialPointerPosition,
    bool continueDragAfterDetach = false,
  }) async {
    if (!Platform.isLinux) return false;
    if (_tabsBeingDetached.contains(detachViewId)) return false;

    final registry = WindowRegistry.maybeOf(context);
    if (registry == null) return false;

    final tabs = ref.read(browserTabControllerProvider);
    final detachIndex = tabs.indexWhere((tab) => tab.viewId == detachViewId);
    if (detachIndex < 0 || tabs.length <= 1) return false;

    _tabsBeingDetached.add(detachViewId);

    final fallbackViewId = detachViewId == currentViewId
        ? tabs[detachIndex == 0 ? 1 : detachIndex - 1].viewId
        : null;

    if (fallbackViewId != null) {
      context.go('/browser/tab/$fallbackViewId');
    }

    final tabController = ref
        .read(browserTabControllerProvider.notifier)
        .take(detachViewId);
    if (tabController == null) {
      _tabsBeingDetached.remove(detachViewId);
      return false;
    }

    DetachedBrowserWindowSession? detachedSession;
    try {
      detachedSession = DetachedBrowserWindowSession(initialTab: tabController);

      final opened = _openDetachedWindowSession(
        registry,
        detachedSession,
        initialPointerPosition: initialPointerPosition,
        continueDragAfterDetach: continueDragAfterDetach,
      );
      if (!opened) {
        throw StateError('Failed to open detached window session');
      }

      _tabsBeingDetached.remove(detachViewId);
      return true;
    } catch (_) {
      ref
          .read(browserTabControllerProvider.notifier)
          .insertAt(detachIndex, tabController);
      detachedSession?.onWindowTitleChanged = null;
      detachedSession?.onEmpty = null;
      detachedSession?.dispose();
      if (fallbackViewId != null) {
        context.go('/browser/tab/$detachViewId');
      }
      _tabsBeingDetached.remove(detachViewId);
      return false;
    }
  }

  static Future<bool> detachTabFromDetachedSessionToNewWindow(
    BuildContext context, {
    required DetachedBrowserWindowSession sourceSession,
    required int detachViewId,
    Offset? initialPointerPosition,
    bool continueDragAfterDetach = false,
  }) async {
    if (!Platform.isLinux) return false;
    if (_tabsBeingDetached.contains(detachViewId)) return false;

    final registry = WindowRegistry.maybeOf(context);
    if (registry == null) return false;

    final tabs = sourceSession.tabs;
    final detachIndex = tabs.indexWhere((tab) => tab.viewId == detachViewId);
    if (detachIndex < 0 || tabs.length <= 1) return false;

    _tabsBeingDetached.add(detachViewId);

    final tabController = sourceSession.takeTab(detachViewId);
    if (tabController == null) {
      _tabsBeingDetached.remove(detachViewId);
      return false;
    }

    DetachedBrowserWindowSession? detachedSession;
    try {
      detachedSession = DetachedBrowserWindowSession(initialTab: tabController);

      final opened = _openDetachedWindowSession(
        registry,
        detachedSession,
        initialPointerPosition: initialPointerPosition,
        continueDragAfterDetach: continueDragAfterDetach,
      );
      if (!opened) {
        throw StateError('Failed to open detached window session');
      }

      _tabsBeingDetached.remove(detachViewId);
      return true;
    } catch (_) {
      sourceSession.insertTabAt(detachIndex, tabController, select: true);
      detachedSession?.onWindowTitleChanged = null;
      detachedSession?.onEmpty = null;
      detachedSession?.dispose();
      _tabsBeingDetached.remove(detachViewId);
      return false;
    }
  }

  static bool _openDetachedWindowSession(
    WindowRegistry registry,
    DetachedBrowserWindowSession session, {
    Offset? initialPointerPosition,
    bool continueDragAfterDetach = false,
  }) {
    final delegate = _DetachedTabWindowDelegate(
      onDestroyed: () => _disposeDetachedSession(session, registry),
    );

    final windowController = RegularWindowController(
      preferredSize: const Size(1040, 760),
      preferredConstraints: const BoxConstraints(minWidth: 640, minHeight: 480),
      title: session.currentWindowTitle,
      delegate: delegate,
    );

    windowController.enableCustomWindow();

    void syncWindowTitle() {
      windowController.setTitle(session.currentWindowTitle);
    }

    session.onWindowTitleChanged = syncWindowTitle;
    session.onEmpty = windowController.destroy;
    syncWindowTitle();

    final entry = WindowEntry(
      controller: windowController,
      builder: (context) {
        return Navigator(
          onGenerateInitialRoutes: (_, __) {
            return [
              MaterialPageRoute<void>(
                builder: (_) {
                  return DetachedTabWindowScreen(session: session);
                },
              ),
            ];
          },
        );
      },
    );

    _detachedSessions[session] = _DetachedTabWindowSession(
      session: session,
      entry: entry,
    );
    registry.register(entry);
    windowController.activate();

    if (continueDragAfterDetach && initialPointerPosition != null) {
      _startCustomWindowMoveDrag(windowController, initialPointerPosition);
    }

    return true;
  }

  static void startWindowDragFromTab(
    BuildContext context, {
    required Offset globalPointerPosition,
  }) {
    final windowController = WindowScope.maybeOf(context);
    if (windowController is RegularWindowController) {
      final started = _startCustomWindowMoveDrag(
        windowController,
        globalPointerPosition,
      );
      if (started) return;
    }

    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      unawaited(windowManager.startDragging());
    }
  }

  static void _disposeDetachedSession(
    DetachedBrowserWindowSession session,
    WindowRegistry registry,
  ) {
    final detachedSession = _detachedSessions.remove(session);
    if (detachedSession == null) return;

    registry.unregister(detachedSession.entry);
    detachedSession.session.onWindowTitleChanged = null;
    detachedSession.session.onEmpty = null;
    detachedSession.session.dispose();
  }

  static bool _startCustomWindowMoveDrag(
    BaseWindowController controller,
    Offset globalPosition,
  ) {
    try {
      controller.enableCustomWindow();
      custom_window.CustomWindow.forController(
        controller,
      )?.startWindowMoveDrag(globalPosition);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool prepareCloseTabNavigation(
    BuildContext context, {
    required int currentViewId,
    required int closeViewId,
    required List<LadybirdController> tabs,
  }) {
    final index = tabs.indexWhere((tab) => tab.viewId == closeViewId);
    if (index < 0) return false;

    if (closeViewId == currentViewId) {
      if (tabs.length == 1) {
        exit(0);
      }

      final destinationIndex = index == 0 ? 1 : index - 1;
      context.go('/browser/tab/${tabs[destinationIndex].viewId}');
    }

    return true;
  }

  static void commitCloseTab(WidgetRef ref, int viewId) {
    ref.read(browserTabControllerProvider.notifier).remove(viewId);
  }

  static void closeTabImmediately(
    WidgetRef ref,
    BuildContext context, {
    required int currentViewId,
    required int closeViewId,
  }) {
    final tabs = ref.read(browserTabControllerProvider);
    final canClose = prepareCloseTabNavigation(
      context,
      currentViewId: currentViewId,
      closeViewId: closeViewId,
      tabs: tabs,
    );
    if (!canClose) return;

    commitCloseTab(ref, closeViewId);
  }
}

class _DetachedTabWindowSession {
  _DetachedTabWindowSession({required this.session, required this.entry});

  final DetachedBrowserWindowSession session;
  final WindowEntry entry;
}

class _DetachedTabWindowDelegate extends RegularWindowControllerDelegate {
  _DetachedTabWindowDelegate({required this.onDestroyed});

  final VoidCallback onDestroyed;
  bool _handledDestroyed = false;

  @override
  void onWindowCloseRequested(RegularWindowController controller) {
    controller.destroy();
  }

  @override
  void onWindowDestroyed() {
    if (_handledDestroyed) return;
    _handledDestroyed = true;
    onDestroyed();
  }
}
