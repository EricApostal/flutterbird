import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BrowserTabBar extends ConsumerStatefulWidget {
  const BrowserTabBar({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends ConsumerState<BrowserTabBar> {
  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabControllerProvider);
    return ReorderableListView.builder(
      scrollDirection: .horizontal,
      itemBuilder: (context, index) {
        return Text(key: ValueKey("re-$index"), "tab");
      },

      itemCount: 10,
      onReorder: (a, b) {},
    );
  }
}
