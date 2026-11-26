// See mac_window_system.dart about the experimental API.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_window/bird_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_macos.dart';
import 'package:ladybird/ladybird.dart';

/// How far a floating window sits from the corner of the screen it opens in.
const double _screenEdgeMargin = 16;

const Size _minimumSize = Size(240, 100);

/// One floating video window.
class MacPictureInPictureWindow {
  MacPictureInPictureWindow._(
    this.viewId,
    this.ownerViewId,
    this.controller,
    this.native,
    this.view,
  );

  /// The engine's view of the video, which this window shows.
  final int viewId;

  /// The tab the video is in.
  final int ownerViewId;
  final WindowController controller;
  final MacWindow native;
  final LadybirdController view;

  /// Starts a drag of the whole window, from a press on the video.
  void startDrag() => native.startDrag();
}

/// The floating windows Picture-in-Picture videos play in. The engine says
/// when to open, resize and close them, and draws their buttons itself.
class MacPictureInPicture extends ChangeNotifier {
  /// [ownerFrame] is where the window of a tab is on screen, if it has one, so
  /// that a video floats on the same screen as the tab it came from.
  MacPictureInPicture({required this.ownerFrame});

  final ScreenRect? Function(int tabId) ownerFrame;

  /// Called when the user asks to go back to the tab a video is in.
  void Function(int tabId)? onReturnToTab;

  final Map<int, MacPictureInPictureWindow> _windows = {};

  List<MacPictureInPictureWindow> get windows =>
      List.unmodifiable(_windows.values);

  void start() {
    final screen =
        MacDesktop.screens().firstOrNull?.visibleFrame ??
        const ScreenRect(0, 0, 1440, 900);
    LadybirdSiteBridge.instance.startPictureInPicture(
      _handle,
      screenWidth: screen.width.round(),
      screenHeight: screen.height.round(),
    );
  }

  void _handle(PictureInPictureEvent event) {
    switch (event.kind) {
      case PictureInPictureEventKind.open:
        _open(event);
      case PictureInPictureEventKind.resize:
        _resize(event);
      case PictureInPictureEventKind.hide:
        final window = _windows[event.viewId];
        if (window != null && !window.controller.isDestroyed) {
          window.native.orderOut();
        }
      case PictureInPictureEventKind.closed:
        _close(event.viewId);
      case PictureInPictureEventKind.backToTab:
        onReturnToTab?.call(event.ownerViewId);
    }
  }

  ScreenRect _screenFor(int tabId) {
    final owner = ownerFrame(tabId);
    if (owner != null) return MacDesktop.visibleFrameAt(owner.center);
    return MacDesktop.screens().firstOrNull?.visibleFrame ??
        const ScreenRect(0, 0, 1440, 900);
  }

  void _open(PictureInPictureEvent event) {
    if (_windows.containsKey(event.viewId)) return;

    final width = event.width.toDouble();
    final height = event.height.toDouble();
    final screen = _screenFor(event.ownerViewId);

    final controller = WindowController(
      size: Size(width, height),
      constraints: BoxConstraints(
        minWidth: _minimumSize.width,
        minHeight: _minimumSize.height,
      ),
      title: 'Picture-in-Picture',
      delegate: _PictureInPictureDelegate(event.viewId),
    );
    final native = MacWindow(
      (controller as WindowControllerMacOS).windowHandle,
    );
    // Dressed and placed before it shows, which is when Flutter has drawn.
    native.useFloatingVideoStyle();
    native.frame = ScreenRect(
      screen.right - width - _screenEdgeMargin,
      screen.bottom - height - _screenEdgeMargin,
      width,
      height,
    );
    native.lockContentAspectRatio(width, height);

    _windows[event.viewId] = MacPictureInPictureWindow._(
      event.viewId,
      event.ownerViewId,
      controller,
      native,
      LadybirdController.fromExistingViewId(viewId: event.viewId),
    );
    notifyListeners();
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The video changed shape. The window stays by the corner of the screen it
  /// is nearest.
  void _resize(PictureInPictureEvent event) {
    final window = _windows[event.viewId];
    if (window == null || window.controller.isDestroyed) return;

    final old = window.native.frame;
    final screen = window.native.visibleScreenFrame;
    final width = event.width.toDouble();
    final height = event.height.toDouble();
    final left = old.center.x > screen.center.x
        ? old.right - width
        : old.left;
    final top = old.center.y > screen.center.y
        ? old.bottom - height
        : old.top;

    window.native.lockContentAspectRatio(width, height);
    window.native.frame = ScreenRect(left, top, width, height);
  }

  /// The engine is done with the window, and is about to drop its view.
  void _close(int viewId) {
    final window = _windows.remove(viewId);
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
        window.view.dispose();
      });
    });
  }
}

class _PictureInPictureDelegate with WindowControllerDelegate {
  _PictureInPictureDelegate(this._viewId);

  final int _viewId;

  // The engine decides when the window goes, and says so.
  @override
  void onWindowCloseRequested(WindowController controller) =>
      LadybirdSiteBridge.instance.closePictureInPicture(_viewId);
}

/// What a floating window holds: the video's view, and the means to move the
/// window by dragging it.
class PictureInPictureView extends StatefulWidget {
  const PictureInPictureView({required this.window, super.key});

  final MacPictureInPictureWindow window;

  @override
  State<PictureInPictureView> createState() => _PictureInPictureViewState();
}

class _PictureInPictureViewState extends State<PictureInPictureView> {
  /// The strip at the bottom where the video's own controls are, whose drags
  /// scrub and are theirs.
  static const double _controlsHeight = 56;
  static const double _dragDistance = 5;

  Offset? _press;
  Size? _reported;

  void _reportSize(Size size) {
    if (size == _reported || size.isEmpty) return;
    _reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LadybirdSiteBridge.instance.pictureInPictureResized(
        widget.window.viewId,
        size.width.round(),
        size.height.round(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _reportSize(constraints.biggest);
          return Listener(
            onPointerDown: (event) {
              final onControls =
                  event.localPosition.dy >
                  constraints.maxHeight - _controlsHeight;
              _press = event.buttons == kPrimaryButton && !onControls
                  ? event.localPosition
                  : null;
            },
            onPointerMove: (event) {
              final press = _press;
              if (press == null) return;
              if ((event.localPosition - press).distance < _dragDistance) {
                return;
              }
              _press = null;
              widget.window.startDrag();
            },
            onPointerUp: (_) => _press = null,
            child: LadybirdView(controller: widget.window.view),
          );
        },
      ),
    );
  }
}
