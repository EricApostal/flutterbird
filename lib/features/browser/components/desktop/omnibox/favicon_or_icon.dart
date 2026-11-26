import 'dart:convert';

import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';

class FaviconOrIcon extends StatelessWidget {
  final String? favicon;
  final BirdGlyph fallback;
  final double size;
  final Color? color;

  const FaviconOrIcon({
    super.key,
    required this.favicon,
    required this.fallback,
    required this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final favicon = this.favicon;
    if (favicon == null || favicon.isEmpty) {
      return BirdIcon(fallback, size: size, color: color);
    }

    if (favicon.startsWith('http://') || favicon.startsWith('https://')) {
      return Image.network(
        favicon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return BirdIcon(fallback, size: size, color: color);
        },
      );
    }

    try {
      final base64Payload = favicon.startsWith('data:')
          ? favicon.substring(favicon.indexOf(',') + 1)
          : favicon;
      final bytes = base64Decode(base64Payload);
      if (bytes.isEmpty) {
        return BirdIcon(fallback, size: size, color: color);
      }

      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return BirdIcon(fallback, size: size, color: color);
        },
      );
    } catch (_) {
      return BirdIcon(fallback, size: size, color: color);
    }
  }
}
