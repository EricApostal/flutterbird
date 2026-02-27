import 'dart:ffi' as ffi;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

typedef GenerateFrameC =
    ffi.Pointer<ffi.Uint8> Function(ffi.Int32 width, ffi.Int32 height);
typedef GenerateFrameDart =
    ffi.Pointer<ffi.Uint8> Function(int width, int height);

typedef FreeFrameC = ffi.Void Function(ffi.Pointer<ffi.Uint8> buffer);
typedef FreeFrameDart = void Function(ffi.Pointer<ffi.Uint8> buffer);

class LadybirdCanvas extends StatefulWidget {
  const LadybirdCanvas({super.key});

  @override
  State<LadybirdCanvas> createState() => _LadybirdCanvasState();
}

class _LadybirdCanvasState extends State<LadybirdCanvas> {
  ui.Image? _currentFrame;
  late ffi.DynamicLibrary _lib;
  late GenerateFrameDart _generateFrame;
  late FreeFrameDart _freeFrame;

  final int _width = 800;
  final int _height = 600;

  @override
  void initState() {
    super.initState();

    // Here come the awful macos signing security errors...
    // const String dylibPath =
    //     '/Users/eric/Documents/development/projects/flutterbird/packages/libbird/cpp/build/libengine.dylib';
    _lib = ffi.DynamicLibrary.process();

    _generateFrame = _lib.lookupFunction<GenerateFrameC, GenerateFrameDart>(
      'generate_frame',
    );
    _freeFrame = _lib.lookupFunction<FreeFrameC, FreeFrameDart>('free_frame');
    _requestNextFrame();
  }

  Future<void> _requestNextFrame() async {
    ffi.Pointer<ffi.Uint8> rawPixels = _generateFrame(_width, _height);
    Uint8List pixelList = rawPixels.asTypedList(_width * _height * 4);

    ui.decodeImageFromPixels(
      pixelList,
      _width,
      _height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        if (mounted) {
          setState(() {
            _currentFrame?.dispose();
            _currentFrame = img;
          });
        }
        _freeFrame(rawPixels);
      },
    );
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
        size: Size(_width.toDouble(), _height.toDouble()),
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
