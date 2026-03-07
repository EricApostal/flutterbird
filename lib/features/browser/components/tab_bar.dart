import 'package:bird_core/bird_core.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/tab.dart';

class BrowserTabBar extends ConsumerStatefulWidget {
  final int currentViewId;
  const BrowserTabBar({super.key, required this.currentViewId});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends ConsumerState<BrowserTabBar> {
  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabControllerProvider);
    final currentTabController = ref.watch(
      browserTabProvider(widget.currentViewId),
    );

    final theme = Theme.of(context);

    return Column(
      children: [
        SizedBox(
          height: 45,
          child: MoveWindow(
            child: Row(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(top: 4, left: 80, bottom: 4),
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      if (index == tabs.length) {
                        return ReorderableDragStartListener(
                          key: ValueKey("close"),
                          index: index,
                          enabled: false,
                          child: IconButton(
                            icon: const Icon(Icons.add, size: 20),
                            onPressed: () {
                              ref
                                  .read(browserTabControllerProvider.notifier)
                                  .add();
                            },
                          ),
                        );
                      }
                      final id = tabs[index].viewId;
                      return ReorderableDragStartListener(
                        key: ValueKey(id),
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2.0),
                          child: BrowserTab(
                            viewId: tabs[index].viewId,
                            selected: id == widget.currentViewId,
                          ),
                        ),
                      );
                    },
                    proxyDecorator:
                        (Widget child, int index, Animation<double> animation) {
                          return Material(
                            color: Colors.transparent,
                            elevation: 0,
                            child: child,
                          );
                        },
                    itemCount: tabs.length + 1,
                    onReorder: (oldIndex, newIndex) {},
                  ),
                ),

                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
          child: TextField(
            onSubmitted: (value) {
              currentTabController.navigate(value);
            },
            controller: currentTabController!.textController,
            decoration: _buildInputDecoration(),
            style: theme.textTheme.labelMedium!.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(200),
              fontWeight: .w500,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration() {
    final theme = Theme.of(context);
    final radius = 12.0;

    return InputDecoration(
      hintText: "Search",
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerLow,

      isDense: true,

      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),

      hintStyle: theme.textTheme.labelMedium!.copyWith(
        color: theme.colorScheme.onSurface.withAlpha(220),
        fontWeight: .w500,
        fontSize: 13,
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(
          color: theme.colorScheme.surfaceContainerHigh,
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
      ),
    );
  }
}
