import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/engine_bindings.g.dart';

void main() {
  runApp(const MaterialApp(home: Scaffold(body: LadybirdCanvas())));
}

class LadybirdCanvas extends StatefulWidget {
  const LadybirdCanvas({super.key});

  @override
  State<LadybirdCanvas> createState() => _LadybirdCanvasState();
}

class _LadybirdCanvasState extends State<LadybirdCanvas> {
  late ffi.DynamicLibrary _lib;
  late LibbirdBindings _bindings;
  int? _textureId;
  static const MethodChannel _channel = MethodChannel('libbird');

  @override
  void initState() {
    super.initState();

    _lib = ffi.DynamicLibrary.process();
    _bindings = LibbirdBindings(_lib);

    _bindings.init_ladybird();

    _createTexture();
  }

  Future<void> _createTexture() async {
    final int textureId = await _channel.invokeMethod('createTexture');

    if (mounted) {
      setState(() {
        _textureId = textureId;
      });
    }
  }

  void _onSizeChanged(Size size) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixelWidth = (size.width * dpr).round();
    final pixelHeight = (size.height * dpr).round();
    final pixelSize = Size(pixelWidth.toDouble(), pixelHeight.toDouble());
    _bindings.resize_window(pixelWidth, pixelHeight);
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

          return Texture(textureId: _textureId!);
        },
      ),
    );
  }
}
