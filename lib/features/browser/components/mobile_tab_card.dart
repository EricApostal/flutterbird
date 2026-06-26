import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';

class MobileTabCard extends ConsumerWidget {
  final int viewId;
  final VoidCallback? onClose;

  const MobileTabCard({super.key, required this.viewId, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(browserTabProvider(viewId));
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);

    if (controller == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                ValueListenableBuilder<dynamic>(
                  valueListenable: controller.faviconNotifier,
                  builder: (context, image, child) {
                    if (image != null) {
                      return RawImage(
                        image: image,
                        width: 16,
                        height: 16,
                        filterQuality: FilterQuality.high,
                      );
                    }
                    return Icon(Icons.public, size: 16, color: theme.colorScheme.onSurface);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: controller.titleNotifier,
                    builder: (context, title, child) {
                      return Text(
                        title.isEmpty ? 'New Tab' : title,
                        style: theme.textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    if (onClose != null) {
                      onClose!();
                    } else {
                      BrowserTabActions.commitCloseTab(ref, viewId);
                    }
                  },
                ),
              ],
            ),
          ),
          // Body (Preview)
          Expanded(
            child: IgnorePointer(
              child: ExcludeFocus(
                child: Container(
                  color: Colors.white,
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      child: Builder(
                        builder: (context) {
                          final density = MediaQuery.devicePixelRatioOf(context);
                          final surfaceW = controller.getSurfaceWidth() / density;
                          final surfaceH = controller.getSurfaceHeight() / density;

                          final w = surfaceW > 0 ? surfaceW : screenSize.width;
                          final h = surfaceH > 0 ? surfaceH : screenSize.height;

                          return SizedBox(
                            width: w,
                            height: h,
                            child: AbsorbPointer(
                              child: LadybirdView(controller: controller),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
