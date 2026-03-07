import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class BrowserTab extends ConsumerWidget {
  final int viewId;
  final bool selected;
  const BrowserTab({super.key, required this.viewId, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browserTab = ref.watch(browserTabProvider(viewId))!;

    final theme = Theme.of(context);
    return Material(
      borderRadius: .circular(8),
      child: InkWell(
        borderRadius: .circular(8),
        onTap: () {
          HapticFeedback.lightImpact();
          context.go("/browser/tab/$viewId");
        },
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.surfaceContainer
                : Colors.transparent,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
              bottom: Radius.circular(8),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        ValueListenableBuilder<dynamic>(
                          valueListenable: browserTab.faviconNotifier,
                          builder: (context, image, child) {
                            if (image != null) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: RawImage(
                                  image: image,
                                  width: 16,
                                  height: 16,
                                  filterQuality: FilterQuality.high,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        Expanded(
                          child: ValueListenableBuilder<String>(
                            valueListenable: browserTab.titleNotifier,
                            builder: (context, title, child) {
                              return Text(
                                title,
                                style: theme.textTheme.labelMedium!.copyWith(
                                  color: selected
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  ref
                      .read(browserTabControllerProvider.notifier)
                      .remove(viewId);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                splashRadius: 16,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
