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

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // TODO: The size should probably be determined by the container, and
    // passed down to engine to resize the viewport
    return SizedBox.expand(child: Texture(textureId: _textureId!));
  }
}
