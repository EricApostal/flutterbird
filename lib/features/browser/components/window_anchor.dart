// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bird_core/bird_core.dart';
import 'package:flutterbird/features/browser/screens/browser.dart';
import 'package:window_toolbox/window_toolbox.dart';

class BrowserWindowAnchor extends ConsumerStatefulWidget {
  final Widget child;

  const BrowserWindowAnchor({super.key, required this.child});

  @override
  ConsumerState<BrowserWindowAnchor> createState() =>
      _BrowserWindowAnchorState();
}

class _BrowserWindowAnchorState extends ConsumerState<BrowserWindowAnchor> {
  final Set<int> _customizedDetachedWindowIds = <int>{};

  @override
  Widget build(BuildContext context) {
    final detachedWindows = ref.watch(
      browserWindowLayoutProvider.select((state) => state.detachedWindows),
    );

    if (detachedWindows.isEmpty) {
      return widget.child;
    }

    final windows = detachedWindows
        .where(
          (window) =>
              window.nativeWindowController != null &&
              window.activeViewId != null,
        )
        .map((window) {
          if (_customizedDetachedWindowIds.add(window.id)) {
            window.nativeWindowController!.enableCustomWindow();
          }

          return RegularWindow(
            controller: window.nativeWindowController!,
            child: BrowserWindowScreen(windowId: window.id),
          );
        })
        .toList();

    if (windows.isEmpty) {
      return widget.child;
    }

    return ViewAnchor(
      view: ViewCollection(views: windows),
      child: widget.child,
    );
  }
}
