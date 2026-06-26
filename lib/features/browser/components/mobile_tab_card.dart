import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';

class MobileTabCard extends ConsumerWidget {
  final int viewId;
  const MobileTabCard({super.key, required this.viewId});

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
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    BrowserTabActions.commitCloseTab(ref, viewId);
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
                      child: SizedBox(
                        width: screenSize.width,
                        height: screenSize.height,
                        child: LadybirdView(controller: controller),
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
