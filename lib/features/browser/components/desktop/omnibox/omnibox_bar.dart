import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_context_menu.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_bookmarks_bar.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_search_field.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_layout_mode.dart';
import 'package:flutterbird/features/browser/state/omnibox_state.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';

enum _ToolbarMenuAction {
  newTab,
  closeCurrentTab,
  copySelection,
  pasteFromClipboard,
  goBack,
  goForward,
  reload,
  openNextTab,
  openPreviousTab,
  toggleBookmark,
  openBookmark,
  toggleTabLayout,
}

class _ToolbarMenuSelection {
  const _ToolbarMenuSelection.action(this.action) : bookmarkUrl = null;

  const _ToolbarMenuSelection.openBookmark(this.bookmarkUrl)
    : action = _ToolbarMenuAction.openBookmark;

  final _ToolbarMenuAction action;
  final String? bookmarkUrl;
}

class BrowserOmniboxBar extends ConsumerStatefulWidget {
  final LadybirdController currentTabController;

  const BrowserOmniboxBar({required this.currentTabController, super.key});

  @override
  ConsumerState<BrowserOmniboxBar> createState() => _BrowserOmniboxBarState();
}

class _BrowserOmniboxBarState extends ConsumerState<BrowserOmniboxBar> {
  final FocusNode _omniboxFocusNode = FocusNode();
  final TextEditingController _omniboxTextController = TextEditingController();
  final GlobalKey _toolbarMenuButtonKey = GlobalKey();
  LadybirdController? _trackedTabController;
  bool _suppressTrackedTextSync = false;
  final Set<int> _hideDefaultSearchHomeForTabs = <int>{};

  @override
  void initState() {
    super.initState();
    _omniboxFocusNode.addListener(_onOmniboxFocusChanged);
    _omniboxTextController.addListener(_onTrackedTextChanged);
    _syncTrackedTabController(widget.currentTabController);
  }

  @override
  void didUpdateWidget(covariant BrowserOmniboxBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTabController != widget.currentTabController) {
      _syncTrackedTabController(widget.currentTabController);
    }
  }

  @override
  void dispose() {
    _syncTrackedTabController(null);
    _omniboxTextController.removeListener(_onTrackedTextChanged);
    _omniboxTextController.dispose();
    _omniboxFocusNode.removeListener(_onOmniboxFocusChanged);
    _omniboxFocusNode.dispose();
    super.dispose();
  }

  void _onOmniboxFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _syncTrackedTabController(LadybirdController? controller) {
    if (_trackedTabController == controller) return;

    _trackedTabController?.urlNotifier.removeListener(_onTrackedUrlChanged);
    _trackedTabController = controller;

    if (controller == null) return;

    if (!controller.hasNavigatedInitial) {
      _hideDefaultSearchHomeForTabs.add(controller.viewId);
      _focusOmniboxForNewTab(controller);
    }

    controller.urlNotifier.addListener(_onTrackedUrlChanged);
    _syncOmniboxTextFromControllerUrl(controller);
    _scheduleInitialUrlSyncIfNeeded(controller);
    final hasBookmarks = ref
        .read(browserOmniboxProvider.select((value) => value.bookmarks))
        .isNotEmpty;
    _scheduleSyncEngineOmnibox(
      controller,
      refreshBookmarks: !hasBookmarks,
      refreshHistory: true,
    );
  }

  void _scheduleInitialUrlSyncIfNeeded(
    LadybirdController controller, {
    int remainingAttempts = 20,
  }) {
    if (remainingAttempts <= 0) return;

    if (!controller.hasStartedNavigation) return;
    if (controller.urlNotifier.value.trim().isNotEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _trackedTabController != controller) return;
      if (controller.urlNotifier.value.trim().isNotEmpty) return;

      controller.syncUrlFromEngine();
      if (controller.urlNotifier.value.trim().isNotEmpty) {
        _syncOmniboxTextFromControllerUrl(controller);
        return;
      }

      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || _trackedTabController != controller) return;
        _scheduleInitialUrlSyncIfNeeded(
          controller,
          remainingAttempts: remainingAttempts - 1,
        );
      });
    });
  }

  void _onTrackedUrlChanged() {
    final controller = _trackedTabController;
    if (controller == null) return;
    _syncHiddenDefaultHomeState(controller);
    _syncOmniboxTextFromControllerUrl(controller);
    _scheduleSyncEngineOmnibox(
      controller,
      refreshBookmarks: false,
      refreshHistory: true,
    );
  }

  void _setOmniboxText(String value) {
    if (_omniboxTextController.text == value) return;
    _suppressTrackedTextSync = true;
    _omniboxTextController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _suppressTrackedTextSync = false;
  }

  void _syncOmniboxTextFromControllerUrl(LadybirdController controller) {
    final omnibox = ref.read(browserOmniboxProvider.notifier);
    final currentUrl = controller.urlNotifier.value;
    final shouldHideDefaultSearchHome =
        _hideDefaultSearchHomeForTabs.contains(controller.viewId) &&
        omnibox.isDefaultSearchHome(controller, currentUrl);
    final displayText = shouldHideDefaultSearchHome ? '' : currentUrl;
    _setOmniboxText(displayText);
  }

  void _focusOmniboxForNewTab(LadybirdController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _trackedTabController != controller) return;
      _omniboxFocusNode.requestFocus();

      final text = _omniboxTextController.text;
      _omniboxTextController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    });
  }

  void _syncHiddenDefaultHomeState(LadybirdController controller) {
    if (!_hideDefaultSearchHomeForTabs.contains(controller.viewId)) return;

    final currentUrl = controller.urlNotifier.value;
    if (currentUrl.trim().isEmpty) return;

    final omnibox = ref.read(browserOmniboxProvider.notifier);
    if (!omnibox.isDefaultSearchHome(controller, currentUrl)) {
      _hideDefaultSearchHomeForTabs.remove(controller.viewId);
    }
  }

  void _onTrackedTextChanged() {
    if (_suppressTrackedTextSync) return;
    final controller = _trackedTabController;
    if (controller == null) return;
    _scheduleSyncEngineOmnibox(
      controller,
      refreshBookmarks: false,
      refreshHistory: true,
    );
  }

  void _scheduleSyncEngineOmnibox(
    LadybirdController controller, {
    required bool refreshBookmarks,
    required bool refreshHistory,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _trackedTabController != controller) return;
      final omnibox = ref.read(browserOmniboxProvider.notifier);
      if (refreshBookmarks) {
        omnibox.refreshBookmarksFromEngine(controller);
      }
      if (refreshHistory) {
        omnibox.refreshHistorySuggestionsFromEngine(
          controller,
          _omniboxTextController.text,
        );
      }
    });
  }

  /// Shared tail for every way the omnibox can commit to a destination:
  /// typing + enter, picking a suggestion, or clicking a bookmark. Keeping
  /// this in one place is what keeps the per-tab hide/text-sync state
  /// consistent across all three entry points.
  void _commitNavigation(LadybirdController controller, String target) {
    if (target.isEmpty) return;
    _omniboxFocusNode.unfocus();
    _hideDefaultSearchHomeForTabs.remove(controller.viewId);
    _setOmniboxText(target);
    controller.navigate(target);
  }

  void _handleOmniboxSubmitted(
    BrowserOmnibox omnibox,
    LadybirdController controller,
    String rawInput,
  ) {
    final target = omnibox.buildNavigationTarget(controller, rawInput.trim());
    _commitNavigation(controller, target);
  }

  void _handleSuggestionSelected(
    BrowserOmnibox omnibox,
    LadybirdController controller,
    OmniboxSuggestion suggestion,
  ) {
    final target =
        suggestion.type == OmniboxSuggestionType.searchAction ||
            suggestion.type == OmniboxSuggestionType.searchQuery
        ? omnibox.buildNavigationTarget(controller, suggestion.value)
        : suggestion.value;
    _commitNavigation(controller, target);
  }

  void _openBookmark(LadybirdController controller, String url) {
    _commitNavigation(controller, url);
  }

  void _navigateToAdjacentTab({
    required LadybirdController currentTabController,
    required bool next,
  }) {
    final tabs = ref.read(browserTabControllerProvider);
    if (tabs.length <= 1) return;

    final currentIndex = tabs.indexWhere(
      (tab) => tab.viewId == currentTabController.viewId,
    );
    if (currentIndex < 0) return;

    final destinationIndex = next
        ? (currentIndex + 1) % tabs.length
        : (currentIndex - 1 + tabs.length) % tabs.length;
    context.go('/browser/tab/${tabs[destinationIndex].viewId}');
  }

  List<BrowserContextMenuItem> _buildToolbarContextMenuItems(
    BrowserOmnibox omnibox,
    LadybirdController currentTabController,
    List<BrowserBookmark> bookmarks,
  ) {
    BrowserContextMenuItem actionItem({
      required _ToolbarMenuAction action,
      required String label,
      bool enabled = true,
    }) {
      return BrowserContextMenuItem.action(
        label: label,
        value: _ToolbarMenuSelection.action(action),
        enabled: enabled,
      );
    }

    final normalizedUrl = omnibox.normalizeUrl(
      currentTabController.urlNotifier.value,
    );
    final hasUrl = normalizedUrl.isNotEmpty;
    final isBookmarked = currentTabController.isCurrentViewBookmarked();
    final canGoBack = currentTabController.canGoBack();
    final canGoForward = currentTabController.canGoForward();

    final bookmarkItems = <BrowserContextMenuItem>[
      actionItem(
        action: _ToolbarMenuAction.toggleBookmark,
        label: isBookmarked ? 'Remove Bookmark' : 'Add Bookmark',
        enabled: hasUrl,
      ),
    ];

    if (bookmarks.isEmpty) {
      bookmarkItems.add(
        const BrowserContextMenuItem.action(
          label: 'No bookmarks yet',
          value: null,
          enabled: false,
        ),
      );
    } else {
      final visibleBookmarks = bookmarks.take(6).toList(growable: false);
      for (final bookmark in visibleBookmarks) {
        bookmarkItems.add(
          BrowserContextMenuItem.action(
            label: bookmark.title,
            value: _ToolbarMenuSelection.openBookmark(bookmark.url),
          ),
        );
      }
    }

    final isVerticalLayout =
        ref.read(browserTabLayoutModeControllerProvider) ==
        BrowserTabLayoutMode.vertical;
    return [
      actionItem(action: _ToolbarMenuAction.newTab, label: 'New Tab'),
      actionItem(
        action: _ToolbarMenuAction.closeCurrentTab,
        label: 'Close Current Tab',
      ),
      const BrowserContextMenuItem.separator(),
      actionItem(
        action: _ToolbarMenuAction.copySelection,
        label: 'Copy Selection',
      ),
      actionItem(action: _ToolbarMenuAction.pasteFromClipboard, label: 'Paste'),
      const BrowserContextMenuItem.separator(),
      actionItem(
        action: _ToolbarMenuAction.goBack,
        label: 'Back',
        enabled: canGoBack,
      ),
      actionItem(
        action: _ToolbarMenuAction.goForward,
        label: 'Forward',
        enabled: canGoForward,
      ),
      actionItem(action: _ToolbarMenuAction.reload, label: 'Reload'),
      actionItem(
        action: _ToolbarMenuAction.openNextTab,
        label: 'Open Next Tab',
      ),
      actionItem(
        action: _ToolbarMenuAction.openPreviousTab,
        label: 'Open Previous Tab',
      ),
      const BrowserContextMenuItem.separator(),
      ...bookmarkItems,
      const BrowserContextMenuItem.separator(),
      actionItem(
        action: _ToolbarMenuAction.toggleTabLayout,
        label: isVerticalLayout
            ? 'Switch to Horizontal Tabs'
            : 'Switch to Vertical Tabs',
      ),
    ];
  }

  Future<void> _showToolbarContextMenu(
    BrowserOmnibox omnibox,
    LadybirdController currentTabController,
    List<BrowserBookmark> bookmarks,
  ) async {
    final buttonContext = _toolbarMenuButtonKey.currentContext;
    if (buttonContext == null) return;

    final buttonRenderObject = buttonContext.findRenderObject();
    if (buttonRenderObject is! RenderBox) return;

    final buttonOrigin = buttonRenderObject.localToGlobal(Offset.zero);
    final selected = await BrowserContextMenuPresenter.show(
      context: context,
      anchorRect: buttonOrigin & buttonRenderObject.size,
      items: _buildToolbarContextMenuItems(
        omnibox,
        currentTabController,
        bookmarks,
      ),
    );

    if (selected is _ToolbarMenuSelection) {
      _onToolbarMenuSelected(omnibox, currentTabController, selected);
    }
  }

  void _onToolbarMenuSelected(
    BrowserOmnibox omnibox,
    LadybirdController currentTabController,
    _ToolbarMenuSelection selection,
  ) {
    switch (selection.action) {
      case _ToolbarMenuAction.newTab:
        BrowserTabActions.openNewTab(ref, context);
        break;
      case _ToolbarMenuAction.closeCurrentTab:
        BrowserTabActions.closeTabImmediately(
          ref,
          context,
          currentViewId: currentTabController.viewId,
          closeViewId: currentTabController.viewId,
        );
        break;
      case _ToolbarMenuAction.copySelection:
        currentTabController.copySelection();
        break;
      case _ToolbarMenuAction.pasteFromClipboard:
        currentTabController.pasteFromClipboard();
        break;
      case _ToolbarMenuAction.goBack:
        currentTabController.goBack();
        break;
      case _ToolbarMenuAction.goForward:
        currentTabController.goForward();
        break;
      case _ToolbarMenuAction.reload:
        currentTabController.reload();
        break;
      case _ToolbarMenuAction.openNextTab:
        _navigateToAdjacentTab(
          currentTabController: currentTabController,
          next: true,
        );
        break;
      case _ToolbarMenuAction.openPreviousTab:
        _navigateToAdjacentTab(
          currentTabController: currentTabController,
          next: false,
        );
        break;
      case _ToolbarMenuAction.toggleBookmark:
        omnibox.toggleBookmarkForCurrentView(currentTabController);
        break;
      case _ToolbarMenuAction.openBookmark:
        final bookmarkUrl = selection.bookmarkUrl;
        if (bookmarkUrl == null || bookmarkUrl.isEmpty) return;
        _openBookmark(currentTabController, bookmarkUrl);
        break;
      case _ToolbarMenuAction.toggleTabLayout:
        ref.read(browserTabLayoutModeControllerProvider.notifier).toggle();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final omniboxController = ref.read(browserOmniboxProvider.notifier);
    final bookmarks = ref.watch(
      browserOmniboxProvider.select((value) => value.bookmarks),
    );
    final currentTabController = widget.currentTabController;

    return Container(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4, top: 4),
        child: Column(
          children: [
            Row(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: currentTabController.canGoBackNotifier,
                  builder: (context, canGoBack, child) {
                    return IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      onPressed: canGoBack
                          ? () {
                              currentTabController.goBack();
                            }
                          : null,
                    );
                  },
                ),

                ValueListenableBuilder<bool>(
                  valueListenable: currentTabController.canGoForwardNotifier,
                  builder: (context, canGoForward, child) {
                    return IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 20),
                      onPressed: canGoForward
                          ? () {
                              currentTabController.goForward();
                            }
                          : null,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    currentTabController.reload();
                  },
                ),
                ValueListenableBuilder<String>(
                  valueListenable: currentTabController.urlNotifier,
                  builder: (context, url, child) {
                    final normalized = omniboxController.normalizeUrl(url);
                    final isBookmarked = currentTabController
                        .isCurrentViewBookmarked();
                    return IconButton(
                      icon: Icon(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                        size: 20,
                      ),
                      tooltip: isBookmarked
                          ? 'Remove bookmark'
                          : 'Add bookmark',
                      onPressed: normalized.isEmpty
                          ? null
                          : () {
                              omniboxController.toggleBookmarkForCurrentView(
                                currentTabController,
                              );
                            },
                    );
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OmniboxSearchField(
                    currentTabController: currentTabController,
                    omniBoxTextController: _omniboxTextController,
                    omniboxFocusNode: _omniboxFocusNode,
                    omniboxController: omniboxController,
                    onSubmitted: (value) => _handleOmniboxSubmitted(
                      omniboxController,
                      currentTabController,
                      value,
                    ),
                    onSuggestionSelected: (suggestion) =>
                        _handleSuggestionSelected(
                          omniboxController,
                          currentTabController,
                          suggestion,
                        ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: _toolbarMenuButtonKey,
                  tooltip: 'Open menu',
                  icon: const Icon(Icons.menu, size: 20),
                  onPressed: () {
                    _showToolbarContextMenu(
                      omniboxController,
                      currentTabController,
                      bookmarks,
                    );
                  },
                ),
              ],
            ),
            if (bookmarks.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OmniboxBookmarksBar(
                  bookmarks: bookmarks,
                  onBookmarkTap: (url) =>
                      _openBookmark(currentTabController, url),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
