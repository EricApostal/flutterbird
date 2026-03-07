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

class _LadybirdViewState extends State<LadybirdView> {
  int? _textureId;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.onResize = () {
      if (mounted) {
        _recreateTexture();
      }
    };
    _recreateTexture();
    _scheduleTick();
    if (!widget.controller.hasNavigatedInitial) {
      widget.controller.hasNavigatedInitial = true;
      widget.controller.navigate(widget.controller.initialUrl);
    }
  }

  void _scheduleTick() {
    /*
    I'm not a huge fan of this but I'm not actually sure there's anything wrong with it
    Ladybird doesn't really have a consistent callback (to my understanding) indicating that
    it needs to be resized. The onResize callback only seems to work with
    */
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

      if (_textureId != null) {
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
        widget.controller.hasNavigatedInitial = true;
        widget.controller.navigate(widget.controller.initialUrl);
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
      if (oldTextureId != null && oldTextureId != textureId) {
        widget.controller.unregisterTexture(oldTextureId);
      }
    } else {
      await widget.controller.unregisterTexture(textureId);
      if (oldTextureId != null) {
        await widget.controller.unregisterTexture(oldTextureId);
      }
    }
  }

  void _onSizeChanged(Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    widget.controller.resizeWindow(size);
  }

  void _onPointerEvent(PointerEvent event, int type) {
    // primary
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

  void _onPointerScroll(PointerScrollEvent event) {
    int type = 4;
    final density = MediaQuery.devicePixelRatioOf(context);
    widget.controller.dispatchMouseEvent(
      type: type,
      x: (event.localPosition.dx * density).toInt(),
      y: (event.localPosition.dy * density).toInt(),
      button: 0,
      buttons: 0,
      modifiers: getModifiersForEvent(
        HardwareKeyboard.instance.logicalKeysPressed,
      ),
      wheelDeltaX: (event.scrollDelta.dx * density).toInt(),
      wheelDeltaY: (event.scrollDelta.dy * density).toInt(),
    );
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    int type = 4;
    final density = MediaQuery.devicePixelRatioOf(context);
    widget.controller.dispatchMouseEvent(
      type: type,
      x: (event.localPosition.dx * density).toInt(),
      y: (event.localPosition.dy * density).toInt(),
      button: 0,
      buttons: 0,
      modifiers: getModifiersForEvent(
        HardwareKeyboard.instance.logicalKeysPressed,
      ),
      wheelDeltaX: -(event.panDelta.dx * density).toInt(),
      wheelDeltaY: -(event.panDelta.dy * density).toInt(),
    );
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
                      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
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
