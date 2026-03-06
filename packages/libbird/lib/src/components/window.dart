import 'package:flutter/material.dart';
import 'package:libbird/src/controller.dart';

class LadybirdView extends StatefulWidget {
  final LadybirdController controller;
  const LadybirdView({super.key, required this.controller});

  @override
  State<LadybirdView> createState() => _LadybirdViewState();
}

class _LadybirdViewState extends State<LadybirdView> {
  int? _textureId;
  @override
  void initState() {
    super.initState();
    _createTexture();
  }

  Future<void> _createTexture() async {
    final int textureId = await widget.controller.createTexture();

    if (mounted) {
      setState(() {
        _textureId = textureId;
      });
    }
  }

  Future<void> _recreateTexture() async {
    final int textureId = await widget.controller.createTexture();

    if (mounted) {
      setState(() {
        _textureId = textureId;
      });
    }
  }

  void _onSizeChanged(Size size) {
    final didResize = widget.controller.resizeWindow(size);
    if (didResize) {
      _recreateTexture();
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
