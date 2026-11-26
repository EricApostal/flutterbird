import 'dart:ui' as ui;

import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/browser/state/tab_preview_cache.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';

/// A tab's page as it last was on screen. It fills its box from the top and is
/// cut off below, so that a card shows the top of a page at full width rather
/// than all of it shrunk to fit.
///
/// A live view per tab would need a whole texture for each of them.
class TabSnapshot extends StatelessWidget {
  const TabSnapshot({required this.tab, super.key});

  final LadybirdController tab;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return ValueListenableBuilder<ui.Image?>(
      valueListenable: TabPreviewCache.instance.listenableFor(tab.viewId),
      builder: (context, image, _) {
        if (image == null) {
          return ColoredBox(
            color: colors.surface,
            child: Center(child: TabIcon(tab: tab, size: 36)),
          );
        }
        return ColoredBox(
          color: colors.surface,
          child: SizedBox.expand(
            child: RawImage(
              image: image,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}
