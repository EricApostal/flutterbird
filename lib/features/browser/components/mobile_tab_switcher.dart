import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/mobile_tab_card.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:go_router/go_router.dart';

class MobileTabSwitcher extends ConsumerStatefulWidget {
  const MobileTabSwitcher({super.key});

  @override
  ConsumerState<MobileTabSwitcher> createState() => _MobileTabSwitcherState();
}

class _MobileTabSwitcherState extends ConsumerState<MobileTabSwitcher> {
  final Map<int, bool> _closingTabs = {};

  void _handleClose(int viewId) async {
    setState(() {
      _closingTabs[viewId] = true;
    });
    // Wait for the animation to finish before actually removing it
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) {
      BrowserTabActions.commitCloseTab(ref, viewId);
      setState(() {
        _closingTabs.remove(viewId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabControllerProvider);
    final theme = Theme.of(context);

    // Filter out tabs that are currently animating their close
    // Wait, if we filter them out, they disappear instantly!
    // We should NOT filter them out from the grid, we just render them with a scale transition.

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainer,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.pop();
          BrowserTabActions.openNewTab(ref, context);
        },
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: tabs.isEmpty
              ? Center(
                  child: Text(
                    'No open tabs',
                    style: theme.textTheme.titleMedium,
                  ),
                )
              : ReorderableGridView.builder(
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
                    final isClosing = _closingTabs[tab.viewId] == true;

                    return AnimatedScale(
                      key: ValueKey(tab.viewId),
                      scale: isClosing ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: isClosing ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: GestureDetector(
                          onTap: () {
                            if (isClosing) return;
                            context.pop();
                            context.go('/browser/tab/${tab.viewId}');
                          },
                          child: MobileTabCard(
                            viewId: tab.viewId,
                            onClose: () => _handleClose(tab.viewId),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
