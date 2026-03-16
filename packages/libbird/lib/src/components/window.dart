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
  final FocusNode _focusNode = FocusNode();

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
    _recreateTexture();
    _scheduleTick();
    if (!widget.controller.hasNavigatedInitial) {
      widget.controller.hasNavigatedInitial = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.controller.navigate(widget.controller.initialUrl),
      );
    }
  }

  void _scheduleTick() {
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
      _scheduleTick();
    });
  }

  @override
  void didUpdateWidget(LadybirdView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.onResize = null;

      if (_textureId != null && _textureId! >= 0) {
        oldWidget.controller.unregisterTexture(_textureId!);
        _textureId = null;
      }

      widget.controller.onResize = () {
        if (mounted) {
          _recreateTexture();
        }
      };

      _recreateTexture();

      if (!widget.controller.hasNavigatedInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.controller.hasNavigatedInitial = true;
          widget.controller.navigate(widget.controller.initialUrl);
        });
      }
    }
  }

  Future<void> _recreateTexture() async {
    final int? oldTextureId = _textureId;
    final int textureId = await widget.controller.createTexture();

    if (mounted) {
      setState(() {
        _textureId = textureId;
      });
      if (oldTextureId != null &&
          oldTextureId >= 0 &&
          oldTextureId != textureId) {
        widget.controller.unregisterTexture(oldTextureId);
      }
    } else {
      if (textureId >= 0) {
        await widget.controller.unregisterTexture(textureId);
      }
      if (oldTextureId != null && oldTextureId >= 0) {
        await widget.controller.unregisterTexture(oldTextureId);
      }
    }
  }

  void _onSizeChanged(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    widget.controller.resizeWindow(size);
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

    int wheelX = _accumulatedWheelX.truncate();
    int wheelY = _accumulatedWheelY.truncate();

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
    _momentumTicker?.dispose();
    _focusNode.dispose();
    print("disposing!");
    if (_textureId != null && _textureId! >= 0) {
      widget.controller.unregisterTexture(_textureId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == -1) {
      return const Center(
        child: Text('Texture channel unavailable in this Android build.'),
      );
    }
    if (_textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final density = MediaQuery.devicePixelRatioOf(context);
          final size = Size(
            constraints.maxWidth * density,
            constraints.maxHeight * density,
          );
          _onSizeChanged(size);

          final paddedWidth = widget.controller.getSurfaceWidth() / density;
          final paddedHeight = widget.controller.getSurfaceHeight() / density;

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
                width: paddedWidth,
                height: paddedHeight,
                child: MouseRegion(
                  onEnter: (_) {
                    if (!_focusNode.hasFocus) {
                      _focusNode.requestFocus();
                    }
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
