import 'dart:ffi' as ffi;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:ffi/ffi.dart' as ffi_pkg;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'src/engine_bindings.g.dart';

void main() {
  runApp(const MaterialApp(home: Scaffold(body: LadybirdCanvas())));
}

class LadybirdCanvas extends StatefulWidget {
  const LadybirdCanvas({super.key});

  @override
  State<LadybirdCanvas> createState() => _LadybirdCanvasState();
}

class _LadybirdCanvasState extends State<LadybirdCanvas>
    with SingleTickerProviderStateMixin {
  ui.Image? _currentFrame;
  late ffi.DynamicLibrary _lib;
  late LibbirdBindings _bindings;
  late Ticker _ticker;

  // Reusing these pointers prevents thrashing the allocator 60 times a second
  late ffi.Pointer<ffi.Int> _widthPtr;
  late ffi.Pointer<ffi.Int> _heightPtr;

  bool _isDecoding = false;

  @override
  void initState() {
    super.initState();

    _lib = ffi.DynamicLibrary.process();
    _bindings = LibbirdBindings(_lib);

    _widthPtr = ffi_pkg.calloc<ffi.Int>();
    _heightPtr = ffi_pkg.calloc<ffi.Int>();

    print("doing init");
    _bindings.init_ladybird();

    // Ticker fires every frame aligned with the display refresh rate
    _ticker = createTicker((elapsed) {
      if (!_isDecoding) {
        _fetchFrame();
      }
    });
    _ticker.start();
  }

  void _fetchFrame() {
    ffi.Pointer<ffi.Uint8> rawPixels = _bindings.get_latest_frame(
      _widthPtr,
      _heightPtr,
    );
    print("got latest");
    print(rawPixels != ffi.nullptr);

    if (rawPixels != ffi.nullptr) {
      _isDecoding = true;
      int width = _widthPtr.value;
      int height = _heightPtr.value;
      int size = width * height * 4;

      // 1. Create a view of the C++ memory
      Uint8List cView = rawPixels.asTypedList(size);

      // 2. Synchronously copy it into Dart-managed memory
      Uint8List dartPixels = Uint8List.fromList(cView);

      // 3. Immediately free the C++ memory so it doesn't leak or trigger OS protections
      _bindings.free_frame(rawPixels);

      // 4. Send the safe Dart copy to the background decoder
      ui.decodeImageFromPixels(
        dartPixels,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (ui.Image img) {
          if (mounted) {
            setState(() {
              _currentFrame?.dispose();
              _currentFrame = img;
            });
          }
          _isDecoding = false;
        },
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    ffi_pkg.calloc.free(_widthPtr);
    ffi_pkg.calloc.free(_heightPtr);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      onTapDown: (details) {
        print(
          "Send to C++: ${details.localPosition.dx}, ${details.localPosition.dy}",
        );
      },
      child: CustomPaint(
        painter: _FramePainter(_currentFrame!),
        size: Size(
          _currentFrame!.width.toDouble(),
          _currentFrame!.height.toDouble(),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final ui.Image image;

  _FramePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
