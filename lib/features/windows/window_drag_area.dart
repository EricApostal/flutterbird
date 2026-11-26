import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';
import 'package:rubisco_browser/features/windows/window_system.dart';

/// Room that behaves like a title bar: dragging it moves the window, and
/// double clicking it maximizes.
class WindowDragArea extends ConsumerWidget {
  const WindowDragArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowId = BrowserWindowScope.of(context);
    final windows = ref.read(windowSystemProvider);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windows.startWindowDrag(windowId),
      onDoubleTap: () => windows.toggleMaximize(windowId),
      child: child,
    );
  }
}
