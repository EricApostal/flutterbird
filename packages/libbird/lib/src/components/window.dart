import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
  Timer? _frameDiagnosticsTimer;
  bool _frameDiagnosticsPollInFlight = false;
  final ValueNotifier<_FrameDiagnosticsSnapshot?> _frameDiagnosticsNotifier =
      ValueNotifier(null);
  _RawFrameDiagnostics? _lastFrameDiagnosticsRaw;

  double _accumulatedWheelX = 0;
  double _accumulatedWheelY = 0;

  Ticker? _momentumTicker;
  Offset _momentumVelocity = Offset.zero;
  Offset _lastPointerPos = Offset.zero;
  int _lastPanTime = 0;

  bool get _showFrameDiagnostics =>
      defaultTargetPlatform == TargetPlatform.macOS;

  void _onNativeResize() {
    if (!mounted) return;
    setState(() {});
  }

  void _onLoadingStateChanged() {
    if (!mounted) return;
  }

  void _attachControllerListeners(LadybirdController controller) {
    controller.addResizeListener(_onNativeResize);
    controller.isLoadingNotifier.addListener(_onLoadingStateChanged);
    controller.mouseCursorNotifier.addListener(_onCursorChanged);
  }

  void _detachControllerListeners(LadybirdController controller) {
    controller.mouseCursorNotifier.removeListener(_onCursorChanged);
    controller.isLoadingNotifier.removeListener(_onLoadingStateChanged);
    controller.removeResizeListener(_onNativeResize);
  }

  void _onCursorChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _momentumTicker = createTicker(_onMomentumTick);
    _attachControllerListeners(widget.controller);

    _recreateTexture();
  }

  @override
  void didUpdateWidget(LadybirdView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachControllerListeners(oldWidget.controller);

      if (_textureId != null) {
        oldWidget.controller.unregisterTexture(_textureId!);
        _textureId = null;
      }

      _stopFrameDiagnostics();

      _attachControllerListeners(widget.controller);

      _recreateTexture();
    }
  }

  Future<void> _recreateTexture() async {
    final int? oldTextureId = _textureId;
    final int textureId = await widget.controller.createTexture();

    if (mounted) {
      setState(() {
        _textureId = textureId;
      });
      _startFrameDiagnosticsIfNeeded();
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

  void _onSizeChanged(Size size, double density) {
    if (size.width <= 0 || size.height <= 0) return;
    final physicalSize = Size(size.width * density, size.height * density);

    debugPrint(
      "[LibBird] _onSizeChanged: flutterSize: $size, density: $density, physicalSize: $physicalSize",
    );

    widget.controller.updateDevicePixelRatio(density);
    widget.controller.resizeWindow(physicalSize);

    if (widget.controller.hasStartedNavigation &&
        widget.controller.urlNotifier.value.trim().isEmpty) {
      widget.controller.syncUrlFromEngine();
    }

    // Ensure first navigation happens only after the native viewport has been
    // sized with the current Flutter constraints and DPR.
    if (!widget.controller.hasNavigatedInitial) {
      widget.controller.hasNavigatedInitial = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentUrl = widget.controller.urlNotifier.value.trim();
        if (widget.controller.hasStartedNavigation || currentUrl.isNotEmpty) {
          return;
        }
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

    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = now - _lastPanTime;

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

  bool _isPlatformShortcutPressed() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => HardwareKeyboard.instance.isMetaPressed,
      _ => HardwareKeyboard.instance.isControlPressed,
    };
  }

  bool _handleClipboardShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }

    if (!_isPlatformShortcutPressed()) {
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      widget.controller.copySelection();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      widget.controller.pasteFromClipboard();
      return true;
    }

    return false;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_handleClipboardShortcut(event)) {
      return KeyEventResult.handled;
    }

    int type = event is KeyDownEvent ? 0 : 1;
    if (event is KeyRepeatEvent) type = 0;

    final keycode = getLadybirdKeyCode(event.logicalKey);
    final codePoint = event.character?.codeUnitAt(0) ?? 0;

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
    _detachControllerListeners(widget.controller);
    _momentumTicker?.dispose();
    _focusNode.dispose();
    _stopFrameDiagnostics();
    _frameDiagnosticsNotifier.dispose();

    if (_textureId != null) {
      widget.controller.unregisterTexture(_textureId!);
    }
    super.dispose();
  }

  void _startFrameDiagnosticsIfNeeded() {
    _frameDiagnosticsTimer?.cancel();
    _frameDiagnosticsTimer = null;
    _frameDiagnosticsPollInFlight = false;
    _frameDiagnosticsNotifier.value = null;
    _lastFrameDiagnosticsRaw = null;

    if (!_showFrameDiagnostics || _textureId == null) {
      return;
    }

    _pollFrameDiagnostics();
    _frameDiagnosticsTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _pollFrameDiagnostics(),
    );
  }

  void _stopFrameDiagnostics() {
    _frameDiagnosticsTimer?.cancel();
    _frameDiagnosticsTimer = null;
    _frameDiagnosticsPollInFlight = false;
    _frameDiagnosticsNotifier.value = null;
    _lastFrameDiagnosticsRaw = null;
  }

  Future<void> _pollFrameDiagnostics() async {
    final textureId = _textureId;
    if (!_showFrameDiagnostics ||
        textureId == null ||
        _frameDiagnosticsPollInFlight) {
      return;
    }

    _frameDiagnosticsPollInFlight = true;
    try {
      final raw = await widget.controller.getTextureDiagnostics(textureId);
      if (!mounted || textureId != _textureId || raw == null) {
        return;
      }

      final next = _RawFrameDiagnostics.fromMap(raw, sampledAt: DateTime.now());
      final snapshot = _FrameDiagnosticsSnapshot.fromRaw(
        next,
        previous: _lastFrameDiagnosticsRaw,
      );

      _lastFrameDiagnosticsRaw = next;
      _frameDiagnosticsNotifier.value = snapshot;
    } finally {
      _frameDiagnosticsPollInFlight = false;
    }
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

          debugPrint(
            "[LibBird] Window.build: constraints=$constraints, density=$density, paddedWidth=$paddedWidth, paddedHeight=$paddedHeight, surfaceWidth=${widget.controller.getSurfaceWidth()}",
          );

          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: paddedWidth,
              minHeight: paddedHeight,
              maxWidth: paddedWidth,
              maxHeight: paddedHeight,
              child: SizedBox(
                width: paddedWidth,
                height: paddedHeight,
                child: MouseRegion(
                  cursor: widget.controller.mouseCursorNotifier.value,
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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Texture(
                            key: ValueKey(_textureId),
                            textureId: _textureId!,
                          ),
                          if (_showFrameDiagnostics)
                            ValueListenableBuilder<_FrameDiagnosticsSnapshot?>(
                              valueListenable: _frameDiagnosticsNotifier,
                              builder: (context, snapshot, child) {
                                if (snapshot == null) {
                                  return const SizedBox.shrink();
                                }
                                return _FrameDiagnosticsOverlay(
                                  snapshot: snapshot,
                                );
                              },
                            ),
                        ],
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

class _RawFrameDiagnostics {
  const _RawFrameDiagnostics({
    required this.sampledAt,
    required this.lastFrameGeneration,
    required this.nativeFrameCallbacks,
    required this.deliveredFrames,
    required this.queuedDrops,
    required this.displayLinkTicks,
    required this.pumpRequests,
    required this.pumpExecutions,
    required this.hasDisplayLink,
    required this.frameNotifyQueued,
  });

  final DateTime sampledAt;
  final int lastFrameGeneration;
  final int nativeFrameCallbacks;
  final int deliveredFrames;
  final int queuedDrops;
  final int displayLinkTicks;
  final int pumpRequests;
  final int pumpExecutions;
  final bool hasDisplayLink;
  final bool frameNotifyQueued;

  factory _RawFrameDiagnostics.fromMap(
    Map<String, Object?> map, {
    required DateTime sampledAt,
  }) {
    int readInt(String key) => (map[key] as num?)?.toInt() ?? 0;

    return _RawFrameDiagnostics(
      sampledAt: sampledAt,
      lastFrameGeneration: readInt('lastFrameGeneration'),
      nativeFrameCallbacks: readInt('nativeFrameCallbacks'),
      deliveredFrames: readInt('deliveredFrames'),
      queuedDrops: readInt('queuedDrops'),
      displayLinkTicks: readInt('displayLinkTicks'),
      pumpRequests: readInt('pumpRequests'),
      pumpExecutions: readInt('pumpExecutions'),
      hasDisplayLink: map['hasDisplayLink'] as bool? ?? false,
      frameNotifyQueued: map['frameNotifyQueued'] as bool? ?? false,
    );
  }
}

class _FrameDiagnosticsSnapshot {
  const _FrameDiagnosticsSnapshot({
    required this.lastFrameGeneration,
    required this.nativeCallbacksPerSecond,
    required this.deliveredFramesPerSecond,
    required this.queuedDropsPerSecond,
    required this.displayLinkTicksPerSecond,
    required this.pumpRequestsPerSecond,
    required this.pumpExecutionsPerSecond,
    required this.deliveryRatio,
    required this.hasDisplayLink,
    required this.frameNotifyQueued,
  });

  final int lastFrameGeneration;
  final double nativeCallbacksPerSecond;
  final double deliveredFramesPerSecond;
  final double queuedDropsPerSecond;
  final double displayLinkTicksPerSecond;
  final double pumpRequestsPerSecond;
  final double pumpExecutionsPerSecond;
  final double deliveryRatio;
  final bool hasDisplayLink;
  final bool frameNotifyQueued;

  factory _FrameDiagnosticsSnapshot.fromRaw(
    _RawFrameDiagnostics current, {
    _RawFrameDiagnostics? previous,
  }) {
    double perSecond(int currentValue, int previousValue, double seconds) {
      if (seconds <= 0) return 0;
      final delta = currentValue >= previousValue
          ? currentValue - previousValue
          : 0;
      return delta / seconds;
    }

    if (previous == null) {
      return _FrameDiagnosticsSnapshot(
        lastFrameGeneration: current.lastFrameGeneration,
        nativeCallbacksPerSecond: 0,
        deliveredFramesPerSecond: 0,
        queuedDropsPerSecond: 0,
        displayLinkTicksPerSecond: 0,
        pumpRequestsPerSecond: 0,
        pumpExecutionsPerSecond: 0,
        deliveryRatio: 0,
        hasDisplayLink: current.hasDisplayLink,
        frameNotifyQueued: current.frameNotifyQueued,
      );
    }

    final elapsedMicroseconds = current.sampledAt
        .difference(previous.sampledAt)
        .inMicroseconds;
    final seconds = elapsedMicroseconds > 0
        ? elapsedMicroseconds / Duration.microsecondsPerSecond
        : 0.0;

    final nativePerSecond = perSecond(
      current.nativeFrameCallbacks,
      previous.nativeFrameCallbacks,
      seconds,
    );
    final deliveredPerSecond = perSecond(
      current.deliveredFrames,
      previous.deliveredFrames,
      seconds,
    );
    final nativeDelta =
        current.nativeFrameCallbacks >= previous.nativeFrameCallbacks
        ? current.nativeFrameCallbacks - previous.nativeFrameCallbacks
        : 0;
    final deliveredDelta = current.deliveredFrames >= previous.deliveredFrames
        ? current.deliveredFrames - previous.deliveredFrames
        : 0;

    return _FrameDiagnosticsSnapshot(
      lastFrameGeneration: current.lastFrameGeneration,
      nativeCallbacksPerSecond: nativePerSecond,
      deliveredFramesPerSecond: deliveredPerSecond,
      queuedDropsPerSecond: perSecond(
        current.queuedDrops,
        previous.queuedDrops,
        seconds,
      ),
      displayLinkTicksPerSecond: perSecond(
        current.displayLinkTicks,
        previous.displayLinkTicks,
        seconds,
      ),
      pumpRequestsPerSecond: perSecond(
        current.pumpRequests,
        previous.pumpRequests,
        seconds,
      ),
      pumpExecutionsPerSecond: perSecond(
        current.pumpExecutions,
        previous.pumpExecutions,
        seconds,
      ),
      deliveryRatio: nativeDelta > 0 ? deliveredDelta / nativeDelta : 0,
      hasDisplayLink: current.hasDisplayLink,
      frameNotifyQueued: current.frameNotifyQueued,
    );
  }
}

class _FrameDiagnosticsOverlay extends StatelessWidget {
  const _FrameDiagnosticsOverlay({required this.snapshot});

  final _FrameDiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: Colors.white,
      fontFamily: 'monospace',
      height: 1.2,
    );

    final lines = <String>[
      'gen ${snapshot.lastFrameGeneration}',
      'native ${snapshot.nativeCallbacksPerSecond.toStringAsFixed(1)}/s',
      'delivered ${snapshot.deliveredFramesPerSecond.toStringAsFixed(1)}/s',
      'coalesced ${snapshot.queuedDropsPerSecond.toStringAsFixed(1)}/s',
      'pump ${snapshot.pumpExecutionsPerSecond.toStringAsFixed(1)}/s',
      'vsync ${snapshot.displayLinkTicksPerSecond.toStringAsFixed(1)}/s ${snapshot.hasDisplayLink ? 'on' : 'off'}',
      'queued ${snapshot.frameNotifyQueued ? 'yes' : 'no'}',
      'delivery ${(snapshot.deliveryRatio * 100).toStringAsFixed(0)}%',
    ];

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(lines.join('\n'), style: textStyle),
        ),
      ),
    );
  }
}
