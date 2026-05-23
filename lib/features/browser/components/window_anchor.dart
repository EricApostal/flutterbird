// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bird_core/bird_core.dart';
import 'package:flutterbird/features/browser/screens/browser.dart';

class BrowserWindowAnchor extends ConsumerWidget {
  final Widget child;

  const BrowserWindowAnchor({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detachedWindows = ref.watch(
      browserWindowLayoutProvider.select((state) => state.detachedWindows),
    );

    if (detachedWindows.isEmpty) {
      return child;
    }

    final windows = detachedWindows
        .where(
          (window) =>
              window.nativeWindowController != null &&
              window.activeViewId != null,
        )
        .map(
          (window) => RegularWindow(
            controller: window.nativeWindowController!,
            child: BrowserWindowScreen(windowId: window.id),
          ),
        )
        .toList();

    if (windows.isEmpty) {
      return child;
    }

    return ViewAnchor(
      view: ViewCollection(views: windows),
      child: child,
    );
  }
}
