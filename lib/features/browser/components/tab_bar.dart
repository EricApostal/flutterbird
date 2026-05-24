import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/tab.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

class BrowserTabBar extends ConsumerStatefulWidget {
  final int currentViewId;
  const BrowserTabBar({super.key, required this.currentViewId});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends ConsumerState<BrowserTabBar>
    with WindowListener {
  static const double _kMacControlsWidth = 78;
  static const double _kRightControlsWidth = 138;

  bool _isWindowMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      windowManager.addListener(this);
      _refreshWindowState();
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _refreshWindowState() async {
    final isMaximized = await windowManager.isMaximized();
    if (!mounted || isMaximized == _isWindowMaximized) return;
    setState(() {
      _isWindowMaximized = isMaximized;
    });
  }

  @override
  void onWindowMaximize() => _refreshWindowState();

  @override
  void onWindowUnmaximize() => _refreshWindowState();

  @override
  void onWindowRestore() => _refreshWindowState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final tabs = ref.watch(browserTabControllerProvider);
    final currentTabController = ref.watch(
      browserTabProvider(widget.currentViewId),
    );

    final isMacOS = Platform.isMacOS;
    final isWindows = Platform.isWindows;
    final isLinux = Platform.isLinux;

    final leftPadding = isMacOS ? _kMacControlsWidth : 8.0;
    final rightPadding = (isWindows || isLinux) ? _kRightControlsWidth : 8.0;

    return Column(
      children: [
        SizedBox(
          height: 45,
          child: DragToMoveArea(
            child: SizedBox(
              width: .infinity,
              child: Padding(
                padding: EdgeInsets.only(
                  left: leftPadding,
                  right: rightPadding,
                ),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    if (index == tabs.length) {
                      return ReorderableDragStartListener(
                        key: ValueKey("add"),
                        index: index,
                        enabled: false,
                        child: IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          onPressed: () {
                            final controller = ref
                                .read(browserTabControllerProvider.notifier)
                                .add();

                            context.go("/browser/tab/${controller.viewId}");
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
                          onTabClosed: () {
                            HapticFeedback.lightImpact();
                            if (id == widget.currentViewId) {
                              if (tabs.length == 1) {
                                // close application
                                exit(0);
                              }
                              if (index == 0) {
                                context.go("/browser/tab/${tabs[1].viewId}");
                              } else {
                                context.go(
                                  "/browser/tab/${tabs[index - 1].viewId}",
                                );
                              }
                            }

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
                  itemCount: tabs.length + 1,
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex == tabs.length) return;
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    if (newIndex >= tabs.length) {
                      newIndex = tabs.length - 1;
                    }
                    ref
                        .read(browserTabControllerProvider.notifier)
                        .reorder(oldIndex, newIndex);
                  },
                ),
              ),
            ),
          ),
        ),
        Container(
          color: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () {
                    currentTabController?.goBack();
                  },
                  splashRadius: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: () {
                    currentTabController?.goForward();
                  },
                  splashRadius: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    currentTabController?.reload();
                  },
                  splashRadius: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: currentTabController!.urlNotifier,
                    builder: (context, url, child) {
                      if (currentTabController.textController.text != url &&
                          !FocusScope.of(context).hasFocus) {
                        currentTabController.textController.text = url;
                      }
                      return TextField(
                        onSubmitted: (value) {
                          currentTabController.navigate(value);
                        },
                        controller: currentTabController.textController,
                        decoration: _buildInputDecoration(),
                        style: theme.textTheme.bodyMedium!,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration() {
    final theme = Theme.of(context);
    final radius = 8.0;

    return InputDecoration(
      hintText: "Search",
      filled: true,
      fillColor: theme.colorScheme.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),

      hintStyle: theme.textTheme.bodyMedium!.copyWith(
        color: theme.colorScheme.onSurface.withAlpha(150),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.surface, width: 1),
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
