import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/mobile_tab_card.dart';
import 'package:flutterbird/features/browser/components/mobile_browser_layout.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:go_router/go_router.dart';

class MobileTabSwitcher extends ConsumerWidget {
  const MobileTabSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(browserTabControllerProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        // App Bar
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: theme.colorScheme.surfaceContainer,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  BrowserTabActions.openNewTab(ref, context);
                  ref.read(mobileTabSwitcherStateProvider.notifier).state = false;
                },
              ),
              Text(
                'Tabs',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  ref.read(mobileTabSwitcherStateProvider.notifier).state = false;
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        // Grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ReorderableGridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.65,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: tabs.length,
              onReorder: (oldIndex, newIndex) {
                ref.read(browserTabControllerProvider.notifier).reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return GestureDetector(
                  key: ValueKey(tab.viewId),
                  onTap: () {
                    ref.read(mobileTabSwitcherStateProvider.notifier).state = false;
                    context.go('/browser/tab/${tab.viewId}');
                  },
                  child: MobileTabCard(
                    viewId: tab.viewId,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
