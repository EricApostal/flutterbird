import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/foundation.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

// The same bytes for the same text, so that Flutter's image cache knows an
// icon it has decoded before and does not flash it in again on a rebuild.
final Map<String, Uint8List> _decoded = {};
const int _mostDecoded = 200;

/// The bytes of a base64 picture, with or without a `data:` prefix, or null
/// when there are none.
Uint8List? decodePicture(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  final cached = _decoded[encoded];
  if (cached != null) return cached;

  final payload = encoded.startsWith('data:')
      ? encoded.substring(encoded.indexOf(',') + 1)
      : encoded;
  try {
    final bytes = base64Decode(payload);
    if (bytes.isEmpty) return null;
    if (_decoded.length >= _mostDecoded) _decoded.remove(_decoded.keys.first);
    return _decoded[encoded] = bytes;
  } on FormatException {
    return null;
  }
}

/// A site's icon from the history or the bookmarks, or its first letter where
/// there is none. No icon is fetched from the network.
class SiteIcon extends StatelessWidget {
  const SiteIcon({required this.url, this.favicon, this.size = 20, super.key});

  final String url;
  final String? favicon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = _Letter(url: url, size: size);
    final bytes = decodePicture(favicon);
    if (bytes == null) return letter;
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => letter,
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final host = siteHost(url);
    final colors = context.mobile;
    if (host.isEmpty) {
      return Icon(Icons.public, size: size, color: colors.textSecondary);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.textSecondary,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Text(
        host.characters.first.toUpperCase(),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: colors.surface,
          fontSize: size * 0.62,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// The icon of the page a tab shows now.
class TabIcon extends StatelessWidget {
  const TabIcon({required this.tab, this.size = 18, this.color, super.key});

  final LadybirdController tab;
  final double size;

  /// Of the icon shown for a page with none of its own.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fallbackColor = color ?? context.mobile.textSecondary;
    return ListenableBuilder(
      listenable: Listenable.merge([tab.faviconNotifier, tab.urlNotifier]),
      builder: (context, _) {
        final image = tab.faviconNotifier.value;
        if (!tab.isOnNewTabPage && image is ui.Image) {
          return RawImage(
            image: image,
            width: size,
            height: size,
            filterQuality: FilterQuality.medium,
          );
        }
        return Icon(
          tab.isOnNewTabPage ? Icons.star_outline_rounded : Icons.public,
          size: size,
          color: fallbackColor,
        );
      },
    );
  }
}

/// A tab's name as the phone interface shows it.
String tabTitle(LadybirdController tab) {
  if (tab.isOnNewTabPage) return 'New tab';
  final title = tab.titleNotifier.value.trim();
  if (title.isNotEmpty && title != 'Tab') return title;
  final url = tab.urlNotifier.value;
  final host = siteHost(url);
  if (host.isNotEmpty) return host;
  return url.isEmpty ? 'New tab' : url;
}

/// What to call a page that may have no title.
String pageTitle(String title, String url) {
  final trimmed = title.trim();
  if (trimmed.isNotEmpty) return trimmed;
  final host = siteHost(url);
  return host.isNotEmpty ? host : url;
}
