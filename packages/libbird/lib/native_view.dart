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
  Size? _lastSize;
  static const MethodChannel _channel = MethodChannel('libbird');

  @override
  void initState() {
    super.initState();

    _lib = ffi.DynamicLibrary.process();
    _bindings = LibbirdBindings(_lib);

    print("doing init");
    _bindings.init_ladybird();
    print("did init");

    _createTexture();
  }

  Future<void> _createTexture() async {
    final int textureId = await _channel.invokeMethod('createTexture');
    print("got id = $textureId");
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
    if (pixelSize == _lastSize) return;
    _lastSize = pixelSize;
    print("resizing to: $pixelSize");
    _channel.invokeMethod('resizeWindow', {
      'width': pixelWidth,
      'height': pixelHeight,
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // Schedule after frame so context is valid for devicePixelRatio lookup
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onSizeChanged(size);
        });
        return SizedBox.expand(child: Texture(textureId: _textureId!));
      },
    );
  }
}
