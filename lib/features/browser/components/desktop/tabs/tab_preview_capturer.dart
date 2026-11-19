import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutterbird/features/browser/state/tab_preview_cache.dart';
import 'package:ladybird/ladybird.dart';

// Keeps the hover-preview snapshot of the tab it wraps up to date while that
// tab is the one on screen. Only the selected tab has a mounted view to read,
// so this is the one chance a tab gets to leave a preview behind for when it
// is in the background.
//
// A snapshot is taken shortly after a load finishes, every few seconds while
// the page is showing (a page changes without loading), and once more as the
// tab goes away.
class TabPreviewCapturer extends StatefulWidget {
  const TabPreviewCapturer({
    super.key,
    required this.controller,
    required this.child,
  });

  final LadybirdController controller;
  final Widget child;

  @override
  State<TabPreviewCapturer> createState() => _TabPreviewCapturerState();
}

class _TabPreviewCapturerState extends State<TabPreviewCapturer> {
  static const Duration _periodicInterval = Duration(seconds: 3);
  static const Duration _settleDelay = Duration(milliseconds: 700);

  Timer? _periodic;
  Timer? _settle;
  bool _wasLoading = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(covariant TabPreviewCapturer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;

    // The screen now shows another tab: leave the old one's last frame behind,
    // then follow the new one.
    _capture(oldWidget.controller);
    _detach(oldWidget.controller);
    _attach(widget.controller);
  }

  @override
  void deactivate() {
    // Best effort: the tab's view may already be on its way out.
    _capture(widget.controller);
    super.deactivate();
  }

  @override
  void dispose() {
    _detach(widget.controller);
    super.dispose();
  }

  void _attach(LadybirdController controller) {
    _wasLoading = controller.isLoadingNotifier.value;
    controller.isLoadingNotifier.addListener(_onLoadingChanged);
    _periodic = Timer.periodic(_periodicInterval, (_) {
      _capture(widget.controller);
    });
    // The tab may open on a page that is already done loading.
    _scheduleSettledCapture();
  }

  void _detach(LadybirdController controller) {
    controller.isLoadingNotifier.removeListener(_onLoadingChanged);
    _periodic?.cancel();
    _periodic = null;
    _settle?.cancel();
    _settle = null;
  }

  void _onLoadingChanged() {
    final isLoading = widget.controller.isLoadingNotifier.value;
    final finished = _wasLoading && !isLoading;
    _wasLoading = isLoading;
    if (finished) _scheduleSettledCapture();
  }

  void _scheduleSettledCapture() {
    _settle?.cancel();
    _settle = Timer(_settleDelay, () => _capture(widget.controller));
  }

  void _capture(LadybirdController controller) {
    // A window that is hidden or minimized isn't painting the page.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached) {
      return;
    }
    unawaited(TabPreviewCache.instance.capture(controller.viewId));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
