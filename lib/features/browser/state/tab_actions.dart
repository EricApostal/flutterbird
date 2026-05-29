// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart' show MaterialPageRoute, Navigator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutterbird/features/browser/screens/detached_tab_window.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';

class BrowserTabActions {
  static final Map<int, _DetachedTabWindowSession> _detachedSessionsByViewId =
      <int, _DetachedTabWindowSession>{};

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
  }) async {
    if (!Platform.isLinux) return false;

    final registry = WindowRegistry.maybeOf(context);
    if (registry == null) return false;

    final tabs = ref.read(browserTabControllerProvider);
    final detachIndex = tabs.indexWhere((tab) => tab.viewId == detachViewId);
    if (detachIndex < 0 || tabs.length <= 1) return false;

    if (_detachedSessionsByViewId.containsKey(detachViewId)) return false;

    final fallbackViewId = detachViewId == currentViewId
        ? tabs[detachIndex == 0 ? 1 : detachIndex - 1].viewId
        : null;

    if (fallbackViewId != null) {
      context.go('/browser/tab/$fallbackViewId');
    }

    final tabController = ref
        .read(browserTabControllerProvider.notifier)
        .take(detachViewId);
    if (tabController == null) return false;

    try {
      final delegate = _DetachedTabWindowDelegate(
        onDestroyed: () => _disposeDetachedSession(detachViewId, registry),
      );

      final windowController = RegularWindowController(
        preferredSize: const Size(1040, 760),
        preferredConstraints: const BoxConstraints(
          minWidth: 640,
          minHeight: 480,
        ),
        title: _windowTitleFor(tabController),
        delegate: delegate,
      );

      void syncWindowTitle() {
        windowController.setTitle(_windowTitleFor(tabController));
      }

      final session = _DetachedTabWindowSession(
        tabController: tabController,
        titleListener: syncWindowTitle,
      );

      tabController.titleNotifier.addListener(syncWindowTitle);

      final entry = WindowEntry(
        controller: windowController,
        builder: (context) {
          return Navigator(
            onGenerateInitialRoutes: (_, __) {
              return [
                MaterialPageRoute<void>(
                  builder: (_) {
                    return DetachedTabWindowScreen(controller: tabController);
                  },
                ),
              ];
            },
          );
        },
      );
      session.entry = entry;

      _detachedSessionsByViewId[detachViewId] = session;
      registry.register(entry);
      windowController.activate();
      return true;
    } catch (_) {
      ref
          .read(browserTabControllerProvider.notifier)
          .insertAt(detachIndex, tabController);
      if (fallbackViewId != null) {
        context.go('/browser/tab/$detachViewId');
      }
      return false;
    }
  }

  static String _windowTitleFor(LadybirdController controller) {
    final title = controller.titleNotifier.value.trim();
    return title.isEmpty ? 'Tab' : title;
  }

  static void _disposeDetachedSession(int viewId, WindowRegistry registry) {
    final session = _detachedSessionsByViewId.remove(viewId);
    if (session == null) return;

    final entry = session.entry;
    if (entry != null) {
      registry.unregister(entry);
    }

    final titleListener = session.titleListener;
    if (titleListener != null) {
      session.tabController.titleNotifier.removeListener(titleListener);
    }
    session.tabController.dispose();
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
  _DetachedTabWindowSession({required this.tabController, this.titleListener});

  final LadybirdController tabController;
  final VoidCallback? titleListener;
  WindowEntry? entry;
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
