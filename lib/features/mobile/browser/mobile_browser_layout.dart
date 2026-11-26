import 'dart:async';
import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/browser/components/browser_window.dart';
import 'package:rubisco_browser/features/browser/state/find_in_page.dart';
import 'package:rubisco_browser/features/browser/state/fullscreen_mode.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';
import 'package:rubisco_browser/features/browser/state/tab_actions.dart';
import 'package:rubisco_browser/features/browser/state/tab_history.dart';
import 'package:rubisco_browser/features/browser/state/tab_preview_cache.dart';
import 'package:rubisco_browser/features/mobile/browser/find_bar.dart';
import 'package:rubisco_browser/features/mobile/browser/mobile_browser_scope.dart';
import 'package:rubisco_browser/features/mobile/browser/mobile_toolbar.dart';
import 'package:rubisco_browser/features/mobile/browser/omnibox_editor.dart';
import 'package:rubisco_browser/features/mobile/browser/overflow_menu.dart';
import 'package:rubisco_browser/features/mobile/browser/page_info_sheet.dart';
import 'package:rubisco_browser/features/mobile/browser/page_menu.dart';
import 'package:rubisco_browser/features/mobile/library/bookmarks_page.dart';
import 'package:rubisco_browser/features/mobile/library/downloads_page.dart';
import 'package:rubisco_browser/features/mobile/library/history_page.dart';
import 'package:rubisco_browser/features/mobile/library/recent_tabs_page.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/settings/mobile_settings_page.dart';
import 'package:rubisco_browser/features/mobile/state/mobile_preferences.dart';
import 'package:rubisco_browser/features/mobile/tabs/tab_snapshot.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

/// The gap between two pages during a swipe from one tab to the next.
const double _tabGap = 18;

// How far a finger goes up or down a page before the toolbar answers.
const double _scrollSlop = 28;

/// The phone's browser screen: the page, and the one toolbar under or over it.
///
/// There is one of these for every tab in turn: showing another tab changes
/// [viewId] and keeps this state.
class MobileBrowserLayout extends ConsumerStatefulWidget {
  final int viewId;

  const MobileBrowserLayout({super.key, required this.viewId});

  @override
  ConsumerState<MobileBrowserLayout> createState() =>
      _MobileBrowserLayoutState();
}

class _MobileBrowserLayoutState extends ConsumerState<MobileBrowserLayout>
    with TickerProviderStateMixin {
  late final AnimationController _editor;

  /// From 0, the toolbar in place, to 1, scrolled out of sight.
  late final AnimationController _toolbarSlide;

  /// How far a swipe between tabs has taken the page, in logical pixels.
  late final AnimationController _tabSlide;

  final GlobalKey _pageKey = GlobalKey();

  bool _editing = false;

  /// Counts the times the address editor was opened, so that each starts
  /// afresh, also one opened while the last is still leaving.
  int _editSession = 0;

  // The page has the toolbar's room while the toolbar is away or on its way,
  // so that it is only laid out again once for each trip.
  bool _toolbarWantedHidden = false;
  bool _pageHasToolbarRoom = false;

  /// The tab whose picture covers the page for the moment it takes the page
  /// itself to be shown after a swipe.
  int? _coverTab;
  Timer? _coverTimer;

  bool _openingTabs = false;
  bool _swiping = false;

  int? _scrollPointer;
  double _scrolled = 0;

  LadybirdController? _watched;

  BrowserShell get _shell => ref.read(browserShellProvider);

  @override
  void initState() {
    super.initState();
    // All made here: one first made while the state is being disposed of would
    // have no ticker to be had.
    _editor = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
    )..addStatusListener(_editorStatusChanged);
    _toolbarSlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _tabSlide = AnimationController.unbounded(vsync: this);
  }

  @override
  void didUpdateWidget(MobileBrowserLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId == widget.viewId) return;
    // Another tab: nothing of the last one's stays up.
    _editing = false;
    _editor.value = 0;
    _toolbarWantedHidden = false;
    _pageHasToolbarRoom = false;
    _toolbarSlide.value = 0;
    // A route change builds this, and an overlay may not change meanwhile.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PageSelectionToolbar.dismiss(),
    );
  }

  @override
  void dispose() {
    _unwatch();
    _coverTimer?.cancel();
    _editor.dispose();
    _toolbarSlide.dispose();
    _tabSlide.dispose();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PageSelectionToolbar.dismiss(),
    );
    super.dispose();
  }

  // ---------------------------------------------------------------- the page

  void _watch(LadybirdController tab) {
    if (identical(_watched, tab)) return;
    _unwatch();
    _watched = tab;
    tab.urlNotifier.addListener(_pageChanged);
    tab.isLoadingNotifier.addListener(_pageChanged);
  }

  void _unwatch() {
    _watched?.urlNotifier.removeListener(_pageChanged);
    _watched?.isLoadingNotifier.removeListener(_pageChanged);
    _watched = null;
  }

  // A page on its way brings the toolbar back.
  void _pageChanged() {
    if (mounted) _setToolbarHidden(false);
  }

  void _setToolbarHidden(bool hidden) {
    if (hidden == _toolbarWantedHidden) return;
    _toolbarWantedHidden = hidden;
    if (hidden) {
      setState(() => _pageHasToolbarRoom = true);
      _toolbarSlide.forward();
      return;
    }
    _toolbarSlide.reverse().whenComplete(() {
      if (!mounted || _toolbarWantedHidden) return;
      setState(() => _pageHasToolbarRoom = false);
    });
  }

  // The toolbar goes as the page is read down and comes back as the finger goes
  // the other way. The engine does not say where a page is scrolled to, so it
  // is the finger that is followed.
  void _onPagePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    // A second finger is a pinch, not a scroll.
    _scrollPointer = _scrollPointer == null ? event.pointer : -1;
    _scrolled = 0;
  }

  void _onPagePointerMove(PointerMoveEvent event, LadybirdController tab) {
    if (event.pointer != _scrollPointer || tab.isOnNewTabPage) return;
    final dy = event.delta.dy;
    if (dy == 0 || dy.abs() < event.delta.dx.abs()) return;
    if (_scrolled.sign != dy.sign) _scrolled = 0;
    _scrolled += dy;
    if (_scrolled.abs() < _scrollSlop) return;
    _setToolbarHidden(_scrolled < 0);
  }

  void _onPagePointerEnd(PointerEvent event) {
    if (event.pointer == _scrollPointer || _scrollPointer == -1) {
      _scrollPointer = null;
    }
  }

  // ---------------------------------------------------------------- address

  void _editAddress() {
    if (_editing) return;
    PageSelectionToolbar.dismiss();
    FindInPage.instance.close(widget.viewId);
    _setToolbarHidden(false);
    setState(() {
      _editing = true;
      _editSession++;
    });
    _editor.forward();
  }

  void _closeEditor() {
    if (!_editing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _editing = false);
    _editor.reverse();
  }

  // The editor stays in the tree while it leaves.
  void _editorStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  void _navigate(LadybirdController tab, String target) {
    _closeEditor();
    if (target.isEmpty) return;
    // The browser's own settings are a screen of the app's here, not a page.
    if (target.startsWith('about:settings') ||
        target.startsWith('chrome://settings')) {
      pushMobilePage<void>(context, const MobileSettingsPage());
      return;
    }
    tab.navigate(target);
  }

  Future<void> _showAddressMenu(LadybirdController tab, Rect anchor) async {
    HapticFeedback.mediumImpact();
    final url = tab.urlNotifier.value;
    final hasPage = !tab.isOnNewTabPage && isShareableUrl(url);
    final atBottom =
        ref.read(mobilePreferencesProvider).addressBar ==
        AddressBarPosition.bottom;

    final choice = await showMobileMenu<String>(
      context: context,
      anchor: anchor,
      width: 260,
      builder: (context) {
        Widget row(IconData icon, String label, String value) => MobileMenuRow(
          icon: icon,
          label: label,
          onTap: () => Navigator.of(context).pop(value),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPage) row(Icons.link_rounded, 'Copy link', 'copy'),
            if (hasPage) row(Icons.share_outlined, 'Share link', 'share'),
            row(Icons.content_paste_go_rounded, 'Paste and go', 'paste'),
            row(
              atBottom
                  ? Icons.vertical_align_top_rounded
                  : Icons.vertical_align_bottom_rounded,
              atBottom
                  ? 'Move address bar to top'
                  : 'Move address bar to bottom',
              'move',
            ),
          ],
        );
      },
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'copy':
        await copyText(context, url);
      case 'share':
        await shareText(context, url);
      case 'paste':
        final text = (await Clipboard.getData(
          Clipboard.kTextPlain,
        ))?.text?.trim();
        if (!mounted || text == null || text.isEmpty) return;
        _navigate(
          tab,
          ref
              .read(browserOmniboxProvider.notifier)
              .buildNavigationTarget(tab, text),
        );
      case 'move':
        _setToolbarHidden(false);
        ref
            .read(mobilePreferencesProvider.notifier)
            .setAddressBar(
              atBottom ? AddressBarPosition.top : AddressBarPosition.bottom,
            );
    }
  }

  // ---------------------------------------------------------------- tabs

  void _newTab() {
    PageSelectionToolbar.dismiss();
    _closeEditor();
    BrowserTabActions.openNewTab(ref, context);
  }

  void _closeThisTab() {
    final shell = _shell;
    final closing = widget.viewId;
    // The last tab is replaced: closing it would close the app, which is not
    // what the menu's "Close tab" asks for.
    if (shell.session.allTabIds.length == 1) {
      shell.openTab(windowId: BrowserWindowScope.of(context));
    }
    shell.closeTab(closing);
  }

  Future<void> _showTabsMenu(Rect anchor) async {
    HapticFeedback.mediumImpact();
    final choice = await showMobileMenu<String>(
      context: context,
      anchor: anchor,
      width: 220,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MobileMenuRow(
            icon: Icons.close,
            label: 'Close tab',
            onTap: () => Navigator.of(context).pop('close'),
          ),
          MobileMenuRow(
            icon: Icons.add_box_outlined,
            label: 'New tab',
            onTap: () => Navigator.of(context).pop('new'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'close') _closeThisTab();
    if (choice == 'new') _newTab();
  }

  Future<void> _openTabSwitcher() async {
    if (_openingTabs) return;
    _openingTabs = true;
    try {
      PageSelectionToolbar.dismiss();
      _closeEditor();
      FindInPage.instance.close(widget.viewId);
      FocusManager.instance.primaryFocus?.unfocus();
      // Back at once rather than sliding, and laid out before the page is
      // measured: the card grows back to where the page will be.
      if (_pageHasToolbarRoom) {
        _toolbarWantedHidden = false;
        _toolbarSlide.value = 0;
        setState(() => _pageHasToolbarRoom = false);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }

      // The switcher shows each tab as it last was on screen, and this one is
      // on screen only until the switcher covers it. A picture that is slow to
      // take is not waited for: the last one will do.
      await TabPreviewCache.instance
          .capture(widget.viewId)
          .timeout(const Duration(milliseconds: 200), onTimeout: () {});
      if (!mounted) return;

      final box = _pageKey.currentContext?.findRenderObject();
      final page = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      // The route stays pushed until the switcher goes to a tab, so this is
      // not waited for. The router keeps what goes with a route as JSON.
      unawaited(
        context.push(
          '/browser/mobile_tabs',
          extra: page == null
              ? null
              : [page.left, page.top, page.width, page.height],
        ),
      );
    } finally {
      _openingTabs = false;
    }
  }

  // ---------------------------------------------------------------- swiping

  List<int> get _tabIds =>
      _shell.session.window(BrowserWindowScope.of(context))?.tabIds ?? const [];

  /// The tab a swipe of [offset] leads to: the one before for a swipe to the
  /// right, the one after for a swipe to the left.
  int? _neighbour(double offset) {
    final tabs = _tabIds;
    final index = tabs.indexOf(widget.viewId);
    if (index < 0 || offset == 0) return null;
    final next = offset > 0 ? index - 1 : index + 1;
    return next < 0 || next >= tabs.length ? null : tabs[next];
  }

  void _onSwipeStart(DragStartDetails details) {
    if (_editing) return;
    _swiping = true;
    _tabSlide.stop();
    PageSelectionToolbar.dismiss();
    // So that coming back shows this tab as it is now.
    unawaited(TabPreviewCache.instance.capture(widget.viewId));
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (!_swiping) return;
    var delta = details.primaryDelta ?? 0;
    final next = _tabSlide.value + delta;
    // With no tab that way, the page gives a little and no more.
    if (next != 0 && _neighbour(next) == null) delta *= 0.2;
    final width = MediaQuery.sizeOf(context).width + _tabGap;
    _tabSlide.value = (_tabSlide.value + delta).clamp(-width, width);
  }

  Future<void> _onSwipeEnd(DragEndDetails details) async {
    if (!_swiping) return;
    _swiping = false;
    final width = MediaQuery.sizeOf(context).width;
    final velocity = details.primaryVelocity ?? 0;
    final offset = _tabSlide.value;
    final target = _neighbour(offset);
    final flung = velocity.abs() > 500 && velocity.sign == offset.sign;

    if (target == null || (offset.abs() < width * 0.35 && !flung)) {
      await _tabSlide.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    await _tabSlide
        .animateTo(
          offset.sign * (width + _tabGap),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .orCancel
        .catchError((_) {});
    // Another swipe may have taken over on the way.
    if (!mounted || _swiping || !_tabIds.contains(target)) return;

    setState(() => _coverTab = target);
    _tabSlide.value = 0;
    _shell.showTab(target);
    _coverTimer?.cancel();
    _coverTimer = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _coverTab = null);
    });
  }

  // ---------------------------------------------------------------- menu

  Future<void> _showMenu(LadybirdController tab, Rect anchor) async {
    PageSelectionToolbar.dismiss();
    final omnibox = ref.read(browserOmniboxProvider.notifier);
    omnibox.refreshBookmarks(tab);
    final url = tab.urlNotifier.value;
    final isWebPage = !tab.isOnNewTabPage && isShareableUrl(url);

    final action = await showOverflowMenu(
      context: context,
      anchor: anchor,
      page: OverflowMenuPage(
        canGoBack: tab.canGoBack(),
        canGoForward: tab.canGoForward(),
        isBookmarked: isWebPage && omnibox.isBookmarked(url),
        isWebPage: isWebPage,
      ),
    );
    // The tab may have closed while the menu was up.
    if (!mounted || action == null || _shell.controllerFor(tab.viewId) != tab) {
      return;
    }

    switch (action) {
      case OverflowAction.back:
        tab.goBack();
      case OverflowAction.forward:
        tab.goForward();
      case OverflowAction.reload:
        tab.reload();
      case OverflowAction.bookmark:
        final wasBookmarked = omnibox.isBookmarked(url);
        omnibox.toggleBookmarkForCurrentView(tab);
        showMobileSnack(
          ScaffoldMessenger.maybeOf(context),
          wasBookmarked ? 'Bookmark removed' : 'Bookmarked',
          action: wasBookmarked ? null : 'See all',
          onAction: () {
            if (mounted) pushMobilePage<void>(context, const BookmarksPage());
          },
        );
      case OverflowAction.pageInfo:
        await showPageInfoSheet(context, tab);
      case OverflowAction.newTab:
        _newTab();
      case OverflowAction.closeTab:
        _closeThisTab();
      case OverflowAction.history:
        await pushMobilePage<void>(context, const HistoryPage());
      case OverflowAction.downloads:
        await pushMobilePage<void>(context, const DownloadsPage());
      case OverflowAction.bookmarks:
        await pushMobilePage<void>(context, const BookmarksPage());
      case OverflowAction.recentTabs:
        await pushMobilePage<void>(context, const RecentTabsPage());
      case OverflowAction.share:
        await shareText(context, url, subject: tab.titleNotifier.value);
      case OverflowAction.findInPage:
        _setToolbarHidden(false);
        FindInPage.instance.open(widget.viewId);
      case OverflowAction.copy:
        tab.copySelection();
      case OverflowAction.paste:
        await tab.pasteFromClipboard();
      case OverflowAction.selectAll:
        tab.selectAll();
      case OverflowAction.settings:
        await pushMobilePage<void>(context, const MobileSettingsPage());
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final viewId = widget.viewId;
    final tab = ref.watch(browserTabProvider(viewId));
    final windowId = BrowserWindowScope.of(context);
    final isFullscreen = ref.watch(
      browserFullscreenModeControllerProvider(windowId),
    );
    final position = ref.watch(
      mobilePreferencesProvider.select((value) => value.addressBar),
    );

    if (tab == null) return const SizedBox.shrink();
    _watch(tab);

    final historyState = ref.watch(tabHistoryControllerProvider(viewId));
    final currentStep = historyState.effectiveCurrentStep;
    final hasHistory =
        currentStep != null && historyState.canPopFrom(currentStep);
    final openerViewId = BrowserTabActions.openerOf(ref, viewId);

    return ListenableBuilder(
      listenable: Listenable.merge([
        FindInPage.instance,
        PageSelectionToolbar.visible,
      ]),
      builder: (context, _) {
        final finding = FindInPage.instance.isOpen(viewId);
        final selecting = PageSelectionToolbar.visible.value;

        // The back button does what it does in a browser, in this order:
        //  1. It puts away what is over the page: the address editor, the
        //     selection toolbar, find in page.
        //  2. The page has history behind it: it goes back through it. That is
        //     the engine going back, and nothing else: the view shows the page
        //     it navigates to, with no animation of ours, because there is no
        //     stack of pages here to animate.
        //  3. The tab was opened by a page and has no history left: close it
        //     and go back to the tab that opened it.
        //  4. Otherwise let the back button through, which leaves the app.
        // While the page is fullscreen, the back button exits that instead
        // (BrowserWindowScreen handles it).
        final goesBack = !isFullscreen && hasHistory;
        final closesTab = !isFullscreen && !hasHistory && openerViewId != null;

        return PopScope(
          canPop: !(_editing || selecting || finding || goesBack || closesTab),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop || isFullscreen) return;
            if (_editing) {
              _closeEditor();
            } else if (selecting) {
              PageSelectionToolbar.dismiss();
            } else if (finding) {
              FindInPage.instance.close(viewId);
            } else if (goesBack) {
              tab.goBack();
            } else if (closesTab) {
              BrowserTabActions.closeTab(
                context,
                currentViewId: viewId,
                closeViewId: viewId,
                destinationViewId: openerViewId,
              );
            }
          },
          child: _screen(
            context,
            tab: tab,
            windowId: windowId,
            isFullscreen: isFullscreen,
            position: position,
            finding: finding,
          ),
        );
      },
    );
  }

  Widget _screen(
    BuildContext context, {
    required LadybirdController tab,
    required int windowId,
    required bool isFullscreen,
    required AddressBarPosition position,
    required bool finding,
  }) {
    final colors = context.mobile;
    final brightness = Theme.of(context).brightness;
    final media = MediaQuery.of(context);
    final safe = isFullscreen ? EdgeInsets.zero : media.viewPadding;
    final keyboard = media.viewInsets.bottom;
    final atBottom = position == AddressBarPosition.bottom;

    // The page makes room for a keyboard it is being typed into. For the
    // address editor's, which covers the page, it stays as it is.
    final typingInPage = keyboard > 0 && !_editing;
    // A bottom toolbar stays behind the keyboard rather than ride up on it.
    final showToolbar =
        !isFullscreen && !finding && !(atBottom && typingInPage);
    final toolbarTakesRoom = showToolbar && !_pageHasToolbarRoom;

    final pageTop =
        safe.top +
        (finding && !isFullscreen ? kMobileFindBarHeight : 0) +
        (!atBottom && toolbarTakesRoom ? kMobileToolbarHeight : 0);
    final pageBottom = typingInPage
        ? math.max(keyboard, safe.bottom)
        : safe.bottom +
              (atBottom && toolbarTakesRoom ? kMobileToolbarHeight : 0);

    final iconBrightness = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: brightness,
        statusBarIconBrightness: iconBrightness,
        systemNavigationBarColor: colors.surface,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: isFullscreen ? Colors.black : colors.surface,
        body: Stack(
          children: [
            Positioned(
              left: safe.left,
              right: safe.right,
              top: pageTop,
              bottom: pageBottom,
              child: _page(tab, windowId),
            ),
            Positioned(
              left: safe.left,
              right: safe.right,
              top: atBottom ? null : safe.top,
              bottom: atBottom ? safe.bottom : null,
              // Kept while out of use, so that its loading line carries on.
              child: Offstage(
                offstage: !showToolbar,
                child: AnimatedBuilder(
                  animation: _toolbarSlide,
                  builder: (context, toolbar) {
                    final t = Curves.easeOutCubic.transform(
                      _toolbarSlide.value,
                    );
                    return FractionalTranslation(
                      translation: Offset(0, atBottom ? t : -t),
                      child: toolbar,
                    );
                  },
                  child: MobileToolbar(
                    tab: tab,
                    position: position,
                    slide: _tabSlide,
                    onHome: () => tab.navigate(tab.newTabUrl),
                    onEditAddress: _editAddress,
                    onAddressMenu: (anchor) => _showAddressMenu(tab, anchor),
                    onSiteInfo: () => showPageInfoSheet(context, tab),
                    onNewTab: _newTab,
                    onTabs: _openTabSwitcher,
                    onTabsMenu: _showTabsMenu,
                    onMenu: (anchor) => _showMenu(tab, anchor),
                    onSwipeStart: _onSwipeStart,
                    onSwipeUpdate: _onSwipeUpdate,
                    onSwipeEnd: _onSwipeEnd,
                  ),
                ),
              ),
            ),
            // The system's bars, over a toolbar that slides under them.
            if (safe.top > 0)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: safe.top,
                child: ColoredBox(color: colors.surface),
              ),
            if (safe.bottom > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: safe.bottom,
                child: ColoredBox(color: colors.surface),
              ),
            if (finding && !isFullscreen)
              Positioned(
                left: safe.left,
                right: safe.right,
                top: safe.top,
                child: MobileFindBar(key: ValueKey(tab.viewId), tab: tab),
              ),
            if (!isFullscreen && (_editing || !_editor.isDismissed))
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_editing,
                  child: OmniboxEditor(
                    key: ValueKey(('editor', tab.viewId, _editSession)),
                    tab: tab,
                    position: position,
                    animation: _editor,
                    onClose: _closeEditor,
                    onNavigate: (target) => _navigate(tab, target),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The page, which moves aside during a swipe between tabs, with the tab it
  /// is swiped towards coming after it.
  Widget _page(LadybirdController tab, int windowId) {
    final page = MobileBrowserScope(
      editAddress: _editAddress,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPagePointerDown,
        onPointerMove: (event) => _onPagePointerMove(event, tab),
        onPointerUp: _onPagePointerEnd,
        onPointerCancel: _onPagePointerEnd,
        child: BrowserWindow(
          key: BrowserWindow.keyFor(windowId, widget.viewId),
          viewId: widget.viewId,
          // The toolbar has its own.
          showLoadingBar: false,
        ),
      ),
    );

    final cover = _coverTab == null ? null : _shell.controllerFor(_coverTab!);

    return LayoutBuilder(
      key: _pageKey,
      builder: (context, constraints) => ClipRect(
        child: AnimatedBuilder(
          animation: _tabSlide,
          child: page,
          builder: (context, page) {
            final offset = _tabSlide.value;
            final neighbourId = _neighbour(offset);
            final neighbour = neighbourId == null
                ? null
                : _shell.controllerFor(neighbourId);
            return Stack(
              fit: StackFit.expand,
              children: [
                Transform.translate(offset: Offset(offset, 0), child: page),
                if (neighbour != null)
                  Transform.translate(
                    offset: Offset(
                      offset - offset.sign * (constraints.maxWidth + _tabGap),
                      0,
                    ),
                    child: TabSnapshot(tab: neighbour),
                  ),
                if (cover != null)
                  IgnorePointer(child: TabSnapshot(tab: cover)),
              ],
            );
          },
        ),
      ),
    );
  }
}
