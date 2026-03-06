import 'package:flutter/material.dart';
import 'package:ladybird/ladybird.dart';

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
    } else {
      widget.controller.unregisterTexture(textureId);
    }
  }

  Future<void> _recreateTexture() async {
    final int textureId = await widget.controller.createTexture();

    if (mounted) {
      final oldId = _textureId;
      setState(() {
        _textureId = textureId;
      });
      // if (oldId != null) {
      //   widget.controller.unregisterTexture(oldId);
      // }
    } else {
      await widget.controller.unregisterTexture(textureId);
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _onSizeChanged(Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final didResize = widget.controller.resizeWindow(size);
    if (didResize) {
      _recreateTexture();
    }
  }

  @override
  void dispose() {
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
                child: Texture(
                  key: ValueKey(_textureId),
                  textureId: _textureId!,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
