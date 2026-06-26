import 'dart:convert';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_context_menu.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_layout_mode.dart';
import 'package:flutterbird/features/browser/state/omnibox_state.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';
import 'package:flutter/services.dart';

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

class MobileOmniboxBar extends ConsumerStatefulWidget {
  final LadybirdController currentTabController;

  const MobileOmniboxBar({required this.currentTabController, super.key});

  @override
  ConsumerState<MobileOmniboxBar> createState() => _MobileOmniboxBarState();
}

class _MobileOmniboxBarState extends ConsumerState<MobileOmniboxBar> {
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
  void didUpdateWidget(covariant MobileOmniboxBar oldWidget) {
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
        omnibox.isDefaultSearchHome(currentUrl);
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
    if (!omnibox.isDefaultSearchHome(currentUrl)) {
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

  Widget _faviconOrIcon({
    required String? favicon,
    required IconData fallback,
    required double size,
    Color? color,
  }) {
    if (favicon == null || favicon.isEmpty) {
      return Icon(fallback, size: size, color: color);
    }

    if (favicon.startsWith('http://') || favicon.startsWith('https://')) {
      return Image.network(
        favicon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Icon(fallback, size: size, color: color);
        },
      );
    }

    try {
      final base64Payload = favicon.startsWith('data:')
          ? favicon.substring(favicon.indexOf(',') + 1)
          : favicon;
      final bytes = base64Decode(base64Payload);
      if (bytes.isEmpty) {
        return Icon(fallback, size: size, color: color);
      }

      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Icon(fallback, size: size, color: color);
        },
      );
    } catch (_) {
      return Icon(fallback, size: size, color: color);
    }
  }

  void _openBookmark(LadybirdController currentTabController, String url) {
    _hideDefaultSearchHomeForTabs.remove(currentTabController.viewId);
    _setOmniboxText(url);
    currentTabController.navigate(url);
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

  Widget _buildBookmarksToolbar(
    ThemeData theme,
    List<BrowserBookmark> bookmarks,
    LadybirdController currentTabController,
  ) {
    if (bookmarks.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final bookmark in bookmarks)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Tooltip(
                message: bookmark.url,
                child: OutlinedButton(
                  onPressed: () {
                    _openBookmark(currentTabController, bookmark.url);
                  },
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    side: BorderSide(width: 0, color: Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _faviconOrIcon(
                        favicon: bookmark.favicon,
                        fallback: Icons.bookmark,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        bookmark.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _submitOmniboxInput(
    BrowserOmnibox omnibox,
    LadybirdController currentTabController,
    String value,
  ) {
    final rawInput = value.trim();
    if (rawInput.isEmpty) return;

    final target = omnibox.buildNavigationTarget(rawInput);
    if (target.isEmpty) return;

    _omniboxFocusNode.unfocus();
    _hideDefaultSearchHomeForTabs.remove(currentTabController.viewId);
    _setOmniboxText(target);
    currentTabController.navigate(target);
  }

  void _onSuggestionSelected(
    BrowserOmnibox omnibox,
    LadybirdController currentTabController,
    OmniboxSuggestion suggestion,
  ) {
    final target =
        suggestion.type == OmniboxSuggestionType.searchAction ||
            suggestion.type == OmniboxSuggestionType.searchQuery
        ? omnibox.buildNavigationTarget(suggestion.value)
        : suggestion.value;

    if (target.isEmpty) return;

    _omniboxFocusNode.unfocus();
    _hideDefaultSearchHomeForTabs.remove(currentTabController.viewId);
    _setOmniboxText(target);
    currentTabController.navigate(target);
  }

  IconData _suggestionIconFor(OmniboxSuggestionType type) {
    switch (type) {
      case OmniboxSuggestionType.bookmark:
        return Icons.bookmark;
      case OmniboxSuggestionType.history:
        return Icons.history;
      case OmniboxSuggestionType.searchQuery:
      case OmniboxSuggestionType.searchAction:
        return Icons.search;
    }
  }

  Widget _suggestionLeading(ThemeData theme, OmniboxSuggestion option) {
    final fallback = _suggestionIconFor(option.type);
    return _faviconOrIcon(
      favicon: option.favicon,
      fallback: fallback,
      size: 18,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  TextSpan _styledUrlSpan(ThemeData theme, String rawUrl) {
    final baseStyle = theme.textTheme.bodyMedium!;
    final primary = baseStyle.copyWith(color: theme.colorScheme.onSurface);
    final secondary = baseStyle.copyWith(
      color: theme.colorScheme.onSurface.withAlpha(140),
    );

    final url = rawUrl.trim();
    if (url.isEmpty) {
      return TextSpan(text: '', style: primary);
    }

    final schemeSeparatorIndex = url.indexOf('://');
    final authorityStart = schemeSeparatorIndex >= 0
        ? schemeSeparatorIndex + 3
        : 0;
    if (authorityStart >= url.length) {
      return TextSpan(text: url, style: primary);
    }

    final delimiters = ['/', '?', '#'];
    var authorityEnd = url.length;
    for (final delimiter in delimiters) {
      final index = url.indexOf(delimiter, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    }

    final authority = url.substring(authorityStart, authorityEnd);
    if (authority.isEmpty) {
      return TextSpan(text: url, style: primary);
    }

    var hostCandidate = authority;
    final userInfoSeparator = hostCandidate.lastIndexOf('@');
    if (userInfoSeparator >= 0 &&
        userInfoSeparator + 1 < hostCandidate.length) {
      hostCandidate = hostCandidate.substring(userInfoSeparator + 1);
    }

    if (hostCandidate.startsWith('[')) {
      final closingBracket = hostCandidate.indexOf(']');
      if (closingBracket > 0) {
        hostCandidate = hostCandidate.substring(0, closingBracket + 1);
      }
    } else {
      final colonIndex = hostCandidate.lastIndexOf(':');
      if (colonIndex > 0 && hostCandidate.indexOf(':') == colonIndex) {
        hostCandidate = hostCandidate.substring(0, colonIndex);
      }
    }

    if (hostCandidate.isEmpty) {
      return TextSpan(text: url, style: primary);
    }

    final hostStart = url.indexOf(hostCandidate, authorityStart);
    if (hostStart < 0) {
      return TextSpan(text: url, style: primary);
    }

    final hostEnd = hostStart + hostCandidate.length;
    final prefix = url.substring(0, hostStart);
    final suffix = url.substring(hostEnd);

    return TextSpan(
      style: secondary,
      children: [
        if (prefix.isNotEmpty) TextSpan(text: prefix),
        TextSpan(text: url.substring(hostStart, hostEnd), style: primary),
        if (suffix.isNotEmpty) TextSpan(text: suffix),
      ],
    );
  }

  Widget _buildStyledOmniboxOverlay(ThemeData theme, String text) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              _styledUrlSpan(theme, text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: StrutStyle.fromTextStyle(theme.textTheme.bodyMedium!),
            ),
          ),
        ),
      ),
    );
  }

  bool _isUrlSuggestion(OmniboxSuggestion option) {
    return option.type == OmniboxSuggestionType.bookmark ||
        option.type == OmniboxSuggestionType.history;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);

          final omniboxController = ref.read(browserOmniboxProvider.notifier);
          final bookmarks = ref.watch(
            browserOmniboxProvider.select((value) => value.bookmarks),
          );
          final currentTabController = widget.currentTabController;

          final radius = 8.0;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Container(
              color: theme.colorScheme.surfaceContainerHigh,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4, top: 4),
                  child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.home, size: 22),
                  onPressed: () {
                    currentTabController.navigate('https://duckduckgo.com/');
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: currentTabController.urlNotifier,
                    builder: (context, url, child) {
                      return RawAutocomplete<OmniboxSuggestion>(
                        textEditingController: _omniboxTextController,
                        focusNode: _omniboxFocusNode,
                        displayStringForOption: (option) => option.value,
                        optionsBuilder: (textEditingValue) {
                          return omniboxController.suggestionsFor(
                            textEditingValue.text,
                          );
                        },
                        onSelected: (suggestion) {
                          _onSuggestionSelected(
                            omniboxController,
                            currentTabController,
                            suggestion,
                          );
                        },
                        fieldViewBuilder:
                            (
                              context,
                              textEditingController,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              return ValueListenableBuilder<TextEditingValue>(
                                valueListenable: textEditingController,
                                builder: (context, editingValue, child) {
                                  final isFocused = focusNode.hasFocus;
                                  return Stack(
                                    children: [
                                      TextField(
                                        onSubmitted: (value) {
                                          _submitOmniboxInput(
                                            omniboxController,
                                            currentTabController,
                                            value,
                                          );
                                          onFieldSubmitted();
                                        },
                                        controller: textEditingController,
                                        focusNode: focusNode,
                                        style: theme.textTheme.bodyMedium!
                                            .copyWith(
                                              fontSize: 13,
                                              color: isFocused
                                                  ? theme.colorScheme.onSurface
                                                  : Colors.transparent,
                                            ),
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: theme.colorScheme.surface,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 12,
                                              ),
                                          hintStyle: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withAlpha(150),
                                              ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              radius,
                                            ),
                                            borderSide: BorderSide(
                                              color: theme.colorScheme.surface,
                                              width: 1,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              radius,
                                            ),
                                            borderSide: BorderSide(
                                              color: theme.colorScheme.primary,
                                              width: 1,
                                            ),
                                          ),
                                          errorBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              radius,
                                            ),
                                            borderSide: BorderSide(
                                              color: theme.colorScheme.error,
                                              width: 1,
                                            ),
                                          ),
                                          focusedErrorBorder:
                                              OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      radius,
                                                    ),
                                                borderSide: BorderSide(
                                                  color:
                                                      theme.colorScheme.error,
                                                  width: 1,
                                                ),
                                              ),
                                        ),
                                      ),
                                      if (!isFocused)
                                        _buildStyledOmniboxOverlay(
                                          theme,
                                          editingValue.text,
                                        ),
                                    ],
                                  );
                                },
                              );
                            },
                        optionsViewBuilder: (context, onSelected, options) {
                          final optionList = options.toList(growable: false);
                          if (optionList.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                  maxHeight: 320,
                                ),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  shrinkWrap: true,
                                  itemCount: optionList.length,
                                  separatorBuilder: (context, index) {
                                    return Divider(
                                      height: 1,
                                      color: theme.colorScheme.outline
                                          .withAlpha(50),
                                    );
                                  },
                                  itemBuilder: (context, index) {
                                    final option = optionList[index];
                                    final isUrlSuggestion = _isUrlSuggestion(
                                      option,
                                    );
                                    final urlText = option.subtitle?.trim();
                                    final hasUrlText =
                                        isUrlSuggestion &&
                                        urlText != null &&
                                        urlText.isNotEmpty;
                                    final title = option.title.trim();
                                    final showTitle =
                                        title.isNotEmpty &&
                                        (!hasUrlText || title != urlText);

                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            _suggestionLeading(theme, option),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (hasUrlText)
                                                    Text.rich(
                                                      _styledUrlSpan(
                                                        theme,
                                                        urlText,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  if (showTitle)
                                                    Text(
                                                      title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: hasUrlText
                                                          ? theme
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                  color: theme
                                                                      .colorScheme
                                                                      .onSurfaceVariant,
                                                                )
                                                          : null,
                                                    ),
                                                  if (!hasUrlText &&
                                                      option.subtitle != null)
                                                    Text(
                                                      option.subtitle!,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Consumer(
                  builder: (context, ref, child) {
                    final tabs = ref.watch(browserTabControllerProvider);
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        context.push('/browser/mobile_tabs');
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.onSurface, width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${tabs.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: _toolbarMenuButtonKey,
                  tooltip: 'Open menu',
                  icon: const Icon(Icons.more_vert, size: 22),
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
                // height: 36,
                width: double.infinity,
                child: _buildBookmarksToolbar(
                  theme,
                  bookmarks,
                  currentTabController,
                ),
              ),
            ],
          ],
        ),
       ),
      ),
     ),
    );
        },
      ),
    );
  }
}
