import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';

class BrowserTabActions {
  static LadybirdController openNewTab(WidgetRef ref, BuildContext context) {
    final controller = ref.read(browserTabControllerProvider.notifier).add();
    context.go('/browser/tab/${controller.viewId}');
    return controller;
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
