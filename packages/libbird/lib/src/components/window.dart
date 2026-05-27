import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:ladybird/ladybird.dart';
import 'keys.dart';

class LadybirdView extends StatefulWidget {
  final LadybirdController controller;
  const LadybirdView({super.key, required this.controller});

  @override
  State<LadybirdView> createState() => _LadybirdViewState();
}

class _LadybirdViewState extends State<LadybirdView>
    with SingleTickerProviderStateMixin {
  int? _textureId;
  bool _textureRecreateInProgress = false;
  bool _textureRecreateQueued = false;
  final FocusNode _focusNode = FocusNode();
  late final VoidCallback _loadingListener;

  double _accumulatedWheelX = 0;
  double _accumulatedWheelY = 0;

  Ticker? _momentumTicker;
  Offset _momentumVelocity = Offset.zero;
  Offset _lastPointerPos = Offset.zero;
  int _lastPanTime = 0;

  @override
  void initState() {
    super.initState();
    _momentumTicker = createTicker(_onMomentumTick);
    widget.controller.onResize = () {
      if (mounted) {
        _recreateTexture();
      }
    };
    widget.controller.onCrossSiteNavigation = () {
      if (!mounted) return;
      print(
        '[Ladybird][Flutter] cross-site navigation process change for view ${widget.controller.viewId}; recreating texture',
      );
      _recreateTextureFromCrossSiteNavigation();
    };

    _loadingListener = () {
      if (mounted) {
        _recreateTexture();
      }
    };
    widget.controller.isLoadingNotifier.addListener(_loadingListener);

    _recreateTexture();
  }

  @override
  void didUpdateWidget(LadybirdView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.onResize = null;
      oldWidget.controller.onCrossSiteNavigation = null;
      oldWidget.controller.isLoadingNotifier.removeListener(_loadingListener);

      widget.controller.onResize = () {
        if (mounted) {
          _recreateTexture();
        }
      };

      widget.controller.onCrossSiteNavigation = () {
        if (!mounted) return;
        print(
          '[Ladybird][Flutter] cross-site navigation process change for view ${widget.controller.viewId}; recreating texture',
        );
        _recreateTextureFromCrossSiteNavigation();
      };
      widget.controller.isLoadingNotifier.addListener(_loadingListener);

      _recreateTexture();
    }
  }

  Future<void> _recreateTexture() async {
    if (_textureRecreateInProgress) {
      _textureRecreateQueued = true;
      return;
    }

    _textureRecreateInProgress = true;
    try {
      do {
        _textureRecreateQueued = false;
        final int? oldTextureId = _textureId;
        final int textureId = await widget.controller.createTexture();

        if (mounted) {
          setState(() {
            _textureId = textureId;
          });
          if (oldTextureId != null && oldTextureId != textureId) {
            widget.controller.unregisterTexture(oldTextureId);
          }
        } else {
          await widget.controller.unregisterTexture(textureId);
          if (oldTextureId != null) {
            await widget.controller.unregisterTexture(oldTextureId);
          }
        }
      } while (_textureRecreateQueued && mounted);
    } finally {
      _textureRecreateInProgress = false;
      _textureRecreateQueued = false;
    }
  }

  Future<void> _recreateTextureFromCrossSiteNavigation() async {
    if (!mounted) return;
    await _recreateTexture();
    if (mounted) {
      setState(() {});
    }
  }

  void _onSizeChanged(Size size, double density) {
    if (size.width <= 0 || size.height <= 0) return;
    final physicalSize = Size(size.width * density, size.height * density);
    print("setting size to ${physicalSize.width}");
    widget.controller.updateDevicePixelRatio(density);
    widget.controller.resizeWindow(physicalSize);

    // Ensure first navigation happens only after the native viewport has been
    // sized with the current Flutter constraints and DPR.
    if (!widget.controller.hasNavigatedInitial) {
      widget.controller.hasNavigatedInitial = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.navigate(widget.controller.initialUrl);
      });
    }
  }

  void _onPointerEvent(PointerEvent event, int type) {
    int button = 1;
    if (event.buttons & kPrimaryMouseButton != 0) {
      button = 1;
    } else if (event.buttons & kSecondaryMouseButton != 0) {
      button = 2;
    }

    if (type == 0 || type == 1) {
      if (event is PointerDownEvent) {
        if (event.buttons == kPrimaryMouseButton) {
          button = 1;
        } else if (event.buttons == kSecondaryMouseButton) {
          button = 2;
        }
      }
    }

    final density = MediaQuery.devicePixelRatioOf(context);
    widget.controller.dispatchMouseEvent(
      type: type,
      x: (event.localPosition.dx * density).toInt(),
      y: (event.localPosition.dy * density).toInt(),
      button: button,
      buttons: event.buttons,
      modifiers: getModifiersForEvent(
        HardwareKeyboard.instance.logicalKeysPressed,
      ),
      wheelDeltaX: 0,
      wheelDeltaY: 0,
    );
  }

  void _dispatchWheelDelta(Offset localPosition, double deltaX, double deltaY) {
    final density = MediaQuery.devicePixelRatioOf(context);

    _accumulatedWheelX += deltaX * density;
    _accumulatedWheelY += deltaY * density;

    double wheelX = _accumulatedWheelX;
    double wheelY = _accumulatedWheelY;

    if (wheelX == 0 && wheelY == 0) return;

    _accumulatedWheelX -= wheelX;
    _accumulatedWheelY -= wheelY;

    widget.controller.dispatchMouseEvent(
      type: 4, // MouseWheel
      x: (localPosition.dx * density).toInt(),
      y: (localPosition.dy * density).toInt(),
      button: 0,
      buttons: 0,
      modifiers: getModifiersForEvent(
        HardwareKeyboard.instance.logicalKeysPressed,
      ),
      wheelDeltaX: wheelX,
      wheelDeltaY: wheelY,
    );
  }

  void _onMomentumTick(Duration elapsed) {
    // If momentum decays below threshold, stop
    if (_momentumVelocity.distance < 0.2) {
      _momentumTicker?.stop();
      _momentumVelocity = Offset.zero;
      return;
    }

    _dispatchWheelDelta(
      _lastPointerPos,
      -_momentumVelocity.dx,
      -_momentumVelocity.dy,
    );

    // Friction factor - adjust this to change how quickly it glides to a stop
    _momentumVelocity *= 0.92;
  }

  void _onPointerScroll(PointerScrollEvent event) {
    _dispatchWheelDelta(
      event.localPosition,
      event.scrollDelta.dx,
      event.scrollDelta.dy,
    );
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _momentumTicker?.stop();
    _momentumVelocity = Offset.zero;
    _lastPointerPos = event.localPosition;
    _lastPanTime = DateTime.now().millisecondsSinceEpoch;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _momentumTicker?.stop();
    _lastPointerPos = event.localPosition;

    int now = DateTime.now().millisecondsSinceEpoch;
    int dt = now - _lastPanTime;

    if (dt > 0 && dt < 100) {
      _momentumVelocity = event.panDelta;
    } else {
      _momentumVelocity = Offset.zero;
    }
    _lastPanTime = now;

    _dispatchWheelDelta(
      event.localPosition,
      -event.panDelta.dx,
      -event.panDelta.dy,
    );
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (_momentumVelocity.distance > 0.5) {
      _momentumTicker?.start();
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    int type = event is KeyDownEvent ? 0 : 1;
    if (event is KeyRepeatEvent) type = 0;

    int keycode = getLadybirdKeyCode(event.logicalKey);
    int codePoint = event.character?.codeUnitAt(0) ?? 0;

    widget.controller.dispatchKeyEvent(
      type: type,
      keycode: keycode,
      modifiers: getModifiersForEvent(
        HardwareKeyboard.instance.logicalKeysPressed,
      ),
      codePoint: codePoint,
      repeat: event is KeyRepeatEvent,
    );
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.controller.onResize = null;
    widget.controller.onCrossSiteNavigation = null;
    widget.controller.isLoadingNotifier.removeListener(_loadingListener);
    _momentumTicker?.dispose();
    _focusNode.dispose();

    if (_textureId != null) {
      widget.controller.unregisterTexture(_textureId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final density = MediaQuery.devicePixelRatioOf(context);
          _onSizeChanged(constraints.biggest, density);

          final paddedWidth = widget.controller.getSurfaceWidth() / density;
          final paddedHeight = widget.controller.getSurfaceHeight() / density;
          final displayWidth = paddedWidth > constraints.maxWidth
              ? paddedWidth
              : constraints.maxWidth;
          final displayHeight = paddedHeight > constraints.maxHeight
              ? paddedHeight
              : constraints.maxHeight;

          print("BUILDING WITH WIDTH: $displayWidth");
          print("padded width = $paddedWidth");

          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: constraints.maxWidth,
              minHeight: constraints.maxHeight,
              maxWidth: paddedWidth > constraints.maxWidth
                  ? paddedWidth
                  : constraints.maxWidth,
              maxHeight: paddedHeight > constraints.maxHeight
                  ? paddedHeight
                  : constraints.maxHeight,
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: MouseRegion(
                  onEnter: (_) {
                    // if (!_focusNode.hasFocus) {
                    //   _focusNode.requestFocus();
                    // }
                  },
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: true,
                    onKeyEvent: _onKeyEvent,
                    child: Listener(
                      onPointerDown: (e) {
                        _focusNode.requestFocus();
                        _onPointerEvent(e, 0);
                      },
                      onPointerUp: (e) => _onPointerEvent(e, 1),
                      onPointerMove: (e) => _onPointerEvent(e, 2),
                      onPointerHover: (e) => _onPointerEvent(e, 2),
                      onPointerPanZoomStart: _onPointerPanZoomStart,
                      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
                      onPointerPanZoomEnd: _onPointerPanZoomEnd,
                      onPointerSignal: (e) {
                        if (e is PointerScrollEvent) {
                          _onPointerScroll(e);
                        }
                      },
                      child: Texture(
                        key: ValueKey(_textureId),
                        textureId: _textureId!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
