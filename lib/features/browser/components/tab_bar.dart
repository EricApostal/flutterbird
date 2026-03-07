import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/tab.dart';

class BrowserTabBar extends ConsumerStatefulWidget {
  const BrowserTabBar({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends ConsumerState<BrowserTabBar> {
  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabControllerProvider);
    final theme = Theme.of(context);
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 4.0, left: 80),
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        return ReorderableDragStartListener(
          key: ValueKey("re-$index"),
          index: index,
          child: Padding(padding: const .only(right: 2.0), child: BrowserTab()),
        );
      },
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return Material(color: Colors.transparent, elevation: 0, child: child);
      },
      itemCount: 10,
      onReorder: (oldIndex, newIndex) {},
    );
  }
}
