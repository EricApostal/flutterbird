import 'dart:ffi' as ffi;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:async';
import 'package:ffi/ffi.dart' as ffi_pkg;
import 'package:flutter/material.dart';

typedef InitLadybirdC = ffi.Void Function();
typedef InitLadybirdDart = void Function();

typedef GetLatestFrameC =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Int32> width,
      ffi.Pointer<ffi.Int32> height,
    );
typedef GetLatestFrameDart =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Int32> width,
      ffi.Pointer<ffi.Int32> height,
    );

typedef FreeFrameC = ffi.Void Function(ffi.Pointer<ffi.Uint8> buffer);
typedef FreeFrameDart = void Function(ffi.Pointer<ffi.Uint8> buffer);

void main() {
  runApp(const MaterialApp(home: Scaffold(body: LadybirdCanvas())));
}

class LadybirdCanvas extends StatefulWidget {
  const LadybirdCanvas({super.key});

  @override
  State<LadybirdCanvas> createState() => _LadybirdCanvasState();
}

class _LadybirdCanvasState extends State<LadybirdCanvas> {
  ui.Image? _currentFrame;
  late ffi.DynamicLibrary _lib;
  late InitLadybirdDart _initLadybird;
  late GetLatestFrameDart _getLatestFrame;
  late FreeFrameDart _freeFrame;
  Timer? _renderLoop;

  @override
  void initState() {
    super.initState();

    _lib = ffi.DynamicLibrary.process();

    _initLadybird = _lib.lookupFunction<InitLadybirdC, InitLadybirdDart>(
      'init_ladybird',
    );
    _getLatestFrame = _lib.lookupFunction<GetLatestFrameC, GetLatestFrameDart>(
      'get_latest_frame',
    );
    _freeFrame = _lib.lookupFunction<FreeFrameC, FreeFrameDart>('free_frame');

    _initLadybird();

    _renderLoop = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _fetchFrame();
    });
  }

  void _fetchFrame() {
    ffi.Pointer<ffi.Int32> widthPtr = ffi_pkg.calloc<ffi.Int32>();
    ffi.Pointer<ffi.Int32> heightPtr = ffi_pkg.calloc<ffi.Int32>();

    ffi.Pointer<ffi.Uint8> rawPixels = _getLatestFrame(widthPtr, heightPtr);

    if (rawPixels != ffi.nullptr) {
      int width = widthPtr.value;
      int height = heightPtr.value;
      Uint8List pixelList = rawPixels.asTypedList(width * height * 4);

      ui.decodeImageFromPixels(
        pixelList,
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
          _freeFrame(rawPixels);
        },
      );
    }

    ffi_pkg.calloc.free(widthPtr);
    ffi_pkg.calloc.free(heightPtr);
  }

  @override
  void dispose() {
    _renderLoop?.cancel();
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
