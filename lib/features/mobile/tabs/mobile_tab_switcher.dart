import 'dart:async';
import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/browser/mobile_toolbar.dart';
import 'package:rubisco_browser/features/mobile/settings/mobile_settings_page.dart';
import 'package:rubisco_browser/features/mobile/state/mobile_preferences.dart';
import 'package:rubisco_browser/features/mobile/tabs/mobile_tab_card.dart';
import 'package:rubisco_browser/features/mobile/tabs/swipe_to_close.dart';
import 'package:rubisco_browser/features/mobile/tabs/tab_snapshot.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

const double _barHeight = 56;
const Duration _undoFor = Duration(seconds: 4);
const Duration _reflow = Duration(milliseconds: 280);

/// The grid of open tabs.
///
/// It is a route of its own, and moves itself with the route's animation: on
/// the way in the page shrinks into its card, and on the way out the chosen
/// card grows into the page.
///
/// A closed tab is only hidden while it can still be brought back, and is
/// closed for good once that has passed, or before anything else happens.
class MobileTabSwitcher extends ConsumerStatefulWidget {
  const MobileTabSwitcher({this.pageRect, super.key});

  /// Where on the screen the page was when the switcher was opened, which is
  /// what a card shrinks from and grows back to.
  final Rect? pageRect;

  @override
  ConsumerState<MobileTabSwitcher> createState() => _MobileTabSwitcherState();
}

class _MobileTabSwitcherState extends ConsumerState<MobileTabSwitcher> {
  final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey();
  late final BrowserShell _shell;
  late final int _windowId;
  ScrollController? _scroll;

  /// The tab whose card is flying: the one the switcher opened from, then the
  /// one chosen.
  int? _hero;
  bool _leaving = false;

  /// Cards shrinking away.
  final Set<int> _closing = {};

  /// Tabs that are closed as far as can be seen, and can still be brought back.
  final List<int> _pending = [];
  Timer? _commitTimer;

  // The card being dragged to another place.
  int? _dragged;
  List<int> _dragOrder = const [];
  Offset _dragFrom = Offset.zero;
  Offset _dragBy = Offset.zero;
  double _dragScrollFrom = 0;
  Offset _finger = Offset.zero;
  Timer? _autoScroll;
  TabGridLayout? _grid;

  @override
  void initState() {
    super.initState();
    _shell = ref.read(browserShellProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scroll != null) return;

    _windowId = BrowserWindowScope.of(context);
    final window = _shell.session.window(_windowId);
    _hero = window?.activeTabId;

    // Opened with the tab being used in sight.
    final media = MediaQuery.of(context);
    final grid = _layoutFor(media);
    final tabs = window?.tabIds ?? const <int>[];
    _scroll = ScrollController(
      initialScrollOffset: grid.scrollOffsetFor(
        _hero == null ? -1 : tabs.indexOf(_hero!),
        tabs.length,
        _viewportHeight(media),
      ),
    );
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _autoScroll?.cancel();
    _scroll?.dispose();
    final pending = [..._pending];
    if (pending.isNotEmpty) {
      final shell = _shell;
      // Not while widgets are being torn down, when providers cannot change.
      Future<void>.microtask(() {
        for (final tabId in pending) {
          shell.closeTab(tabId, stayPut: true);
        }
      });
    }
    super.dispose();
  }

  TabGridLayout _layoutFor(MediaQueryData media) => TabGridLayout.fit(
    width: media.size.width - media.viewPadding.horizontal,
    height: media.size.height - media.viewPadding.vertical,
  );

  double _viewportHeight(MediaQueryData media) =>
      math.max(0, media.size.height - media.viewPadding.vertical - _barHeight);

  // ---------------------------------------------------------------- leaving

  void _dismiss([int? to]) {
    if (_leaving) return;
    _commit();
    final tabId = to ?? _shell.session.window(_windowId)?.activeTabId;
    // With no tab left there is nothing to go back to but out of the app.
    if (tabId == null) {
      SystemNavigator.pop();
      return;
    }
    _leaving = true;
    setState(() => _hero = tabId);
    _shell.showTab(tabId);
  }

  void _newTab() {
    if (_leaving) return;
    _commit();
    _leaving = true;
    final tab = _shell.openTab(windowId: _windowId);
    setState(() => _hero = tab.viewId);
  }

  // ---------------------------------------------------------------- closing

  Future<void> _closeWithButton(int tabId) async {
    if (_dragged != null || !_closing.add(tabId)) return;
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 170));
    if (mounted && _closing.contains(tabId)) _markClosed([tabId]);
  }

  void _markClosed(List<int> tabIds) {
    if (tabIds.isEmpty) return;
    setState(() {
      _closing.removeAll(tabIds);
      _pending.addAll(tabIds.where((id) => !_pending.contains(id)));
    });
    _commitTimer?.cancel();
    _commitTimer = Timer(_undoFor, _commit);
    _offerUndo();
  }

  void _offerUndo() {
    if (_pending.isEmpty) return;
    final only = _pending.length == 1
        ? _shell.controllerFor(_pending.first)
        : null;
    final atBottom =
        ref.read(mobilePreferencesProvider).addressBar ==
        AddressBarPosition.bottom;
    showMobileSnack(
      _messenger.currentState,
      only != null
          ? 'Closed ${tabTitle(only)}'
          : '${_pending.length} tabs closed',
      action: 'Undo',
      onAction: _undo,
      bottomGap: atBottom ? _barHeight + 8 : 12,
      duration: _undoFor,
    );
  }

  void _undo() {
    _commitTimer?.cancel();
    if (mounted) setState(_pending.clear);
  }

  void _commit() {
    _commitTimer?.cancel();
    if (_pending.isEmpty) return;
    _messenger.currentState?.hideCurrentSnackBar();
    for (final tabId in _pending) {
      _shell.closeTab(tabId, stayPut: true);
    }
    _pending.clear();
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- dragging

  void _startDrag(int tabId, LongPressStartDetails details) {
    final grid = _grid;
    final scroll = _scroll;
    if (grid == null || scroll == null || _leaving) return;
    // With nothing waiting to close, the cards are the window's tabs.
    _commit();
    final tabs = _shell.session.window(_windowId)?.tabIds ?? const <int>[];
    final index = tabs.indexOf(tabId);
    if (index < 0) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _dragged = tabId;
      _dragOrder = [...tabs];
      _dragFrom = Offset(grid.leftOf(index), grid.topOf(index));
      _dragBy = Offset.zero;
      _dragScrollFrom = scroll.offset;
      _finger = details.globalPosition;
    });
    _autoScroll = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _scrollNearEdge(),
    );
  }

  void _updateDrag(LongPressMoveUpdateDetails details) {
    if (_dragged == null) return;
    _finger = details.globalPosition;
    _dragBy = details.offsetFromOrigin;
    _placeDragged();
  }

  Offset get _draggedAt =>
      _dragFrom + _dragBy + Offset(0, (_scroll!.offset - _dragScrollFrom));

  void _placeDragged() {
    final grid = _grid;
    final tabId = _dragged;
    if (grid == null || tabId == null) return;
    final middle = _draggedAt + Offset(grid.cardWidth / 2, grid.cardHeight / 2);
    final target = grid.indexAt(middle.dx, middle.dy, _dragOrder.length);
    final current = _dragOrder.indexOf(tabId);
    setState(() {
      if (current >= 0 && target != current) {
        _dragOrder = [..._dragOrder]
          ..removeAt(current)
          ..insert(target, tabId);
        HapticFeedback.selectionClick();
      }
    });
  }

  // A card held near the top or bottom brings more of the grid to it.
  void _scrollNearEdge() {
    final scroll = _scroll;
    if (_dragged == null || scroll == null || !scroll.hasClients) return;
    final media = MediaQuery.of(context);
    final top = media.viewPadding.top + _barHeight + 24;
    final bottom =
        media.size.height - media.viewPadding.bottom - _barHeight - 24;
    final step = _finger.dy < top ? -9.0 : (_finger.dy > bottom ? 9.0 : 0.0);
    if (step == 0) return;
    final next = (scroll.offset + step).clamp(
      scroll.position.minScrollExtent,
      scroll.position.maxScrollExtent,
    );
    if (next == scroll.offset) return;
    scroll.jumpTo(next);
    _placeDragged();
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    final tabId = _dragged;
    if (tabId == null) return;
    final session = _shell.session;
    final from = session.window(_windowId)?.tabIds.indexOf(tabId) ?? -1;
    final to = _dragOrder.indexOf(tabId);
    if (from >= 0 && to >= 0) {
      ref
          .read(browserSessionProvider.notifier)
          .commit(session.reorderTab(_windowId, from, to));
    }
    setState(() {
      _dragged = null;
      _dragOrder = const [];
    });
  }

  // ---------------------------------------------------------------- menu

  Future<void> _showMenu(Rect anchor, List<int> shown) async {
    final choice = await showMobileMenu<String>(
      context: context,
      anchor: anchor,
      width: 230,
      builder: (context) {
        Widget row(IconData icon, String label, String? value) => MobileMenuRow(
          icon: icon,
          label: label,
          onTap: value == null ? null : () => Navigator.of(context).pop(value),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(Icons.add_box_outlined, 'New tab', 'new'),
            row(
              Icons.close,
              'Close all tabs',
              shown.isEmpty ? null : 'closeAll',
            ),
            row(Icons.settings_outlined, 'Settings', 'settings'),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case 'new':
        _newTab();
      case 'closeAll':
        _markClosed(shown);
      case 'settings':
        await pushMobilePage<void>(context, const MobileSettingsPage());
    }
  }

  // ---------------------------------------------------------------- build

  /// The tab to mark: the window's, or its neighbour while it is closing.
  int? _selected(List<int> tabs, List<int> shown) {
    final active = _shell.session.window(_windowId)?.activeTabId;
    if (active == null || shown.contains(active)) return active;
    final index = tabs.indexOf(active);
    for (var i = index - 1; i >= 0; i--) {
      if (shown.contains(tabs[i])) return tabs[i];
    }
    return shown.isEmpty ? null : shown.first;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final brightness = Theme.of(context).brightness;
    final media = MediaQuery.of(context);
    final safe = media.viewPadding;
    final atBottom =
        ref.watch(
          mobilePreferencesProvider.select((value) => value.addressBar),
        ) ==
        AddressBarPosition.bottom;
    final all = ref.watch(windowTabsProvider(_windowId));
    final tabs = [
      for (final tab in all)
        if (!_pending.contains(tab.viewId)) tab,
    ];
    final shown = [for (final tab in tabs) tab.viewId];
    final selected = _selected([for (final tab in all) tab.viewId], shown);
    final grid = _grid = _layoutFor(media);
    final animation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final curved = animation.drive(
      CurveTween(curve: Curves.easeInOutCubicEmphasized),
    );

    final bar = _TopBar(
      count: shown.length,
      onNewTab: _newTab,
      onMenu: (anchor) => _showMenu(anchor, shown),
    );

    final iconBrightness = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _dismiss(selected);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: brightness,
          statusBarIconBrightness: iconBrightness,
          systemNavigationBarColor: colors.surface,
          systemNavigationBarIconBrightness: iconBrightness,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: FadeTransition(
                opacity: curved,
                child: ColoredBox(color: colors.surface),
              ),
            ),
            Positioned.fill(
              child: FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
                  child: ScaffoldMessenger(
                    key: _messenger,
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Padding(
                        padding: safe,
                        child: Column(
                          children: [
                            if (!atBottom) bar,
                            Expanded(
                              child: tabs.isEmpty
                                  ? const _NoTabs()
                                  : _cards(grid, tabs, selected, animation),
                            ),
                            if (atBottom) bar,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _flight(grid, shown, curved, animation, atBottom, media),
          ],
        ),
      ),
    );
  }

  Widget _cards(
    TabGridLayout grid,
    List<LadybirdController> tabs,
    int? selected,
    Animation<double> animation,
  ) {
    final byId = {for (final tab in tabs) tab.viewId: tab};
    final order = _dragged == null
        ? byId.keys.toList()
        : [
            for (final id in _dragOrder)
              if (byId.containsKey(id)) id,
          ];
    // The dragged card is painted last, over the others. Cards are known by
    // their tab, so changing the order here moves none of their state.
    final painted = [
      for (final id in order)
        if (id != _dragged) id,
      if (_dragged != null && byId.containsKey(_dragged)) _dragged!,
    ];

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: _scroll,
        physics: _dragged != null
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          width: constraints.maxWidth,
          height: math.max(
            grid.contentHeight(order.length),
            constraints.maxHeight,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final id in painted)
                _positioned(
                  grid,
                  byId[id]!,
                  order.indexOf(id),
                  selected: id == selected,
                  animation: animation,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positioned(
    TabGridLayout grid,
    LadybirdController tab,
    int index, {
    required bool selected,
    required Animation<double> animation,
  }) {
    final id = tab.viewId;
    final lifted = id == _dragged;
    final closing = _closing.contains(id);
    final at = lifted
        ? _draggedAt
        : Offset(grid.leftOf(index), grid.topOf(index));

    return AnimatedPositioned(
      key: ValueKey(id),
      duration: lifted ? Duration.zero : _reflow,
      curve: Curves.easeOutCubic,
      left: at.dx,
      top: at.dy,
      width: grid.cardWidth,
      height: grid.cardHeight,
      child: SwipeToClose(
        enabled: _dragged == null && !closing,
        onClosed: () => _markClosed([id]),
        child: AnimatedScale(
          scale: closing ? 0.75 : (lifted ? 1.05 : 1),
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: closing ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: GestureDetector(
              onTap: closing ? null : () => _dismiss(id),
              onLongPressStart: (details) => _startDrag(id, details),
              onLongPressMoveUpdate: _updateDrag,
              onLongPressEnd: (_) => _endDrag(),
              onLongPressCancel: _endDrag,
              // Its place is kept empty while its picture is in flight.
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, card) => Opacity(
                  opacity: id == _hero && !animation.isCompleted ? 0 : 1,
                  child: card,
                ),
                child: MobileTabCard(
                  tab: tab,
                  selected: selected,
                  lifted: lifted,
                  onClose: () => _closeWithButton(id),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The picture on its way between the whole page and its card.
  Widget _flight(
    TabGridLayout grid,
    List<int> shown,
    Animation<double> curved,
    Animation<double> animation,
    bool atBottom,
    MediaQueryData media,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final hero = _hero;
        final tab = hero == null ? null : _shell.controllerFor(hero);
        final index = hero == null ? -1 : shown.indexOf(hero);
        if (animation.isCompleted || tab == null || index < 0) {
          return const SizedBox.shrink();
        }
        final safe = media.viewPadding;
        final scroll = _scroll!;
        final scrolled = scroll.hasClients
            ? scroll.offset
            : scroll.initialScrollOffset;
        final card = Rect.fromLTWH(
          safe.left + grid.leftOf(index) + kTabCardInset,
          safe.top +
              (atBottom ? 0 : _barHeight) +
              grid.topOf(index) -
              scrolled +
              kTabCardHeader,
          grid.cardWidth - 2 * kTabCardInset,
          grid.cardHeight - kTabCardHeader - kTabCardInset,
        );
        final page = widget.pageRect ?? Offset.zero & media.size;
        final t = curved.value;
        return Positioned.fromRect(
          rect: Rect.lerp(page, card, t)!,
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kTabThumbnailRadius * t),
              child: TabSnapshot(tab: tab),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.count,
    required this.onNewTab,
    required this.onMenu,
  });

  final int count;
  final VoidCallback onNewTab;
  final ValueChanged<Rect> onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return SizedBox(
      height: _barHeight,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'New tab',
            iconSize: 28,
            icon: Icon(Icons.add, color: colors.text),
            onPressed: onNewTab,
          ),
          Expanded(
            child: Center(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  color: colors.accentContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabCountBadge(
                      count: count,
                      color: colors.onAccentContainer,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      count == 1 ? 'Tab' : 'Tabs',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.onAccentContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Menu',
              icon: Icon(Icons.more_vert, color: colors.text),
              onPressed: () => onMenu(globalRectOf(context)),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _NoTabs extends StatelessWidget {
  const _NoTabs();

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tab_rounded, size: 56, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'You\'ll find your tabs here',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: colors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Open tabs to visit different pages at the same time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
