import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/engine_bindings.g.dart';

class LadybirdView extends StatefulWidget {
  const LadybirdView({super.key});

  @override
  State<LadybirdView> createState() => _LadybirdViewState();
}

class _LadybirdViewState extends State<LadybirdView> {
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

  Future<void> _recreateTexture() async {
    final int? oldId = _textureId;
    final int textureId = await _channel.invokeMethod('createTexture');
    if (oldId != null) {
      // await _channel.invokeMethod('unregisterTexture', oldId);
    }
    if (mounted) {
      setState(() {
        _textureId = textureId;
      });
    }
  }

  void _onSizeChanged(Size size) {
    if (_lastSize == size) return;
    _lastSize = size;

    _bindings.resize_window(size.width.toInt(), size.height.toInt());

    _recreateTexture();
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

          return Texture(key: ValueKey(_textureId), textureId: _textureId!);
        },
      ),
    );
  }
}
