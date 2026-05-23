import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/tab.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';

class BrowserTabBar extends ConsumerWidget {
  final int windowId;
  final int currentViewId;

  const BrowserTabBar({
    super.key,
    required this.windowId,
    required this.currentViewId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layoutController = ref.read(browserWindowLayoutProvider.notifier);

    final allTabs = ref.watch(browserTabControllerProvider);
    final windowTabIds = ref.watch(browserWindowTabIdsProvider(windowId));
    final tabById = {for (final tab in allTabs) tab.viewId: tab};
    final tabs = windowTabIds
        .map((viewId) => tabById[viewId])
        .whereType<LadybirdController>()
        .toList();

    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final resolvedCurrentViewId = windowTabIds.contains(currentViewId)
        ? currentViewId
        : tabs.first.viewId;

    final currentTabController = ref.watch(
      browserTabProvider(resolvedCurrentViewId),
    );

    final isDetachedWindow = windowId != mainBrowserWindowId;
    final doLeftPadding = Platform.isMacOS;

    return Column(
      children: [
        if (isDetachedWindow)
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Swipe a tab down to merge it back into the main window.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        SizedBox(
          height: 45,
          child: Stack(
            children: [
              MoveWindow(),
              Padding(
                padding: EdgeInsets.only(left: doLeftPadding ? 80 : 8),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  itemCount: tabs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == tabs.length) {
                      return Container(
                        key: const ValueKey('add'),
                        padding: const EdgeInsets.only(left: 4),
                        child: IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          onPressed: () {
                            final controller = ref
                                .read(browserTabControllerProvider.notifier)
                                .add();

                            layoutController.addTabToWindow(
                              windowId,
                              controller.viewId,
                              makeActive: true,
                            );

                            if (!isDetachedWindow) {
                              context.go('/browser/tab/${controller.viewId}');
                            }
                          },
                        ),
                      );
                    }

                    final id = tabs[index].viewId;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(id),
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: BrowserTab(
                          viewId: id,
                          selected: id == resolvedCurrentViewId,
                          onTabSelected: () {
                            layoutController.setActiveTab(windowId, id);
                            if (!isDetachedWindow) {
                              context.go('/browser/tab/$id');
                            }
                          },
                          onTabDraggedDown: () {
                            HapticFeedback.mediumImpact();

                            if (isDetachedWindow) {
                              final merged = layoutController.mergeTabToMain(
                                tabId: id,
                                fromWindowId: windowId,
                              );
                              if (merged) {
                                context.go('/browser/tab/$id');
                              }
                              return;
                            }

                            final detachedWindowId = layoutController.detachTab(
                              tabId: id,
                              fromWindowId: windowId,
                            );
                            if (detachedWindowId == null) {
                              return;
                            }

                            final updatedLayout = ref.read(
                              browserWindowLayoutProvider,
                            );
                            final activeMainTab = updatedLayout
                                .windowById(mainBrowserWindowId)
                                ?.activeViewId;
                            if (activeMainTab != null) {
                              context.go('/browser/tab/$activeMainTab');
                            }
                          },
                          onTabClosed: () {
                            HapticFeedback.lightImpact();
                            if (allTabs.length == 1) {
                              exit(0);
                            }

                            final fallbackTab = layoutController
                                .fallbackTabAfterClose(windowId, id);

                            if (id == resolvedCurrentViewId &&
                                fallbackTab != null) {
                              if (isDetachedWindow) {
                                layoutController.setActiveTab(
                                  windowId,
                                  fallbackTab,
                                );
                              } else {
                                context.go('/browser/tab/$fallbackTab');
                              }
                            }

                            layoutController.removeTab(id);
                            ref
                                .read(browserTabControllerProvider.notifier)
                                .remove(id);
                          },
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
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex == tabs.length) {
                      return;
                    }
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    if (newIndex >= tabs.length) {
                      newIndex = tabs.length - 1;
                    }

                    layoutController.reorderTab(windowId, oldIndex, newIndex);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => currentTabController?.goBack(),
                splashRadius: 20,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: () => currentTabController?.goForward(),
                splashRadius: 20,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => currentTabController?.reload(),
                splashRadius: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: currentTabController == null
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<String>(
                        valueListenable: currentTabController.urlNotifier,
                        builder: (context, url, child) {
                          if (currentTabController.textController.text != url &&
                              !FocusScope.of(context).hasFocus) {
                            currentTabController.textController.text = url;
                          }
                          return TextField(
                            onSubmitted: currentTabController.navigate,
                            controller: currentTabController.textController,
                            decoration: _buildInputDecoration(context),
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(BuildContext context) {
    final theme = Theme.of(context);
    const radius = 12.0;

    return InputDecoration(
      hintText: 'Search',
      filled: true,
      fillColor: theme.colorScheme.surfaceContainer,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: theme.textTheme.bodyMedium!.copyWith(
        color: theme.colorScheme.onSurface.withAlpha(200),
        fontWeight: FontWeight.w500,
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
