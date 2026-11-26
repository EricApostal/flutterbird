import 'package:bird_core/bird_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/browser/mobile_progress_bar.dart';
import 'package:rubisco_browser/features/mobile/state/mobile_preferences.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

const double kMobileToolbarHeight = 60;

/// How tall the address bar's rounded field is.
const double kMobileAddressHeight = 44;

const double _buttonWidth = 46;
const double _edge = 4;

// Narrower than this, the home button gives its room to the address.
const double _roomForHome = 340;

/// How far the address bar is from the toolbar's sides, so that the field the
/// address is typed in can grow out of it.
({double left, double right}) mobileAddressInsets(double toolbarWidth) => (
  left: toolbarWidth >= _roomForHome ? _edge + _buttonWidth : 12,
  right: _edge + 3 * _buttonWidth,
);

/// The browser's one toolbar: home, the address, a new tab, the tab switcher
/// and the menu.
///
/// A swipe along it goes to the tab beside this one, and a swipe from it
/// towards the page opens the tab switcher.
class MobileToolbar extends ConsumerWidget {
  const MobileToolbar({
    required this.tab,
    required this.position,
    required this.slide,
    required this.onHome,
    required this.onEditAddress,
    required this.onAddressMenu,
    required this.onSiteInfo,
    required this.onNewTab,
    required this.onTabs,
    required this.onTabsMenu,
    required this.onMenu,
    required this.onSwipeStart,
    required this.onSwipeUpdate,
    required this.onSwipeEnd,
    super.key,
  });

  final LadybirdController tab;
  final AddressBarPosition position;

  /// How far a swipe between tabs has gone, in logical pixels.
  final ValueListenable<double> slide;
  final VoidCallback onHome;
  final VoidCallback onEditAddress;
  final ValueChanged<Rect> onAddressMenu;
  final VoidCallback onSiteInfo;
  final VoidCallback onNewTab;
  final VoidCallback onTabs;
  final ValueChanged<Rect> onTabsMenu;
  final ValueChanged<Rect> onMenu;
  final GestureDragStartCallback onSwipeStart;
  final GestureDragUpdateCallback onSwipeUpdate;
  final GestureDragEndCallback onSwipeEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.mobile;
    final atBottom = position == AddressBarPosition.bottom;
    final tabCount = ref
        .watch(windowTabsProvider(BrowserWindowScope.of(context)))
        .length;

    return Material(
      color: colors.surface,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: onSwipeStart,
        onHorizontalDragUpdate: onSwipeUpdate,
        onHorizontalDragEnd: onSwipeEnd,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          // Towards the page: up from the bottom, down from the top.
          if (atBottom ? velocity < -250 : velocity > 250) onTabs();
        },
        child: SizedBox(
          height: kMobileToolbarHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showHome = constraints.maxWidth >= _roomForHome;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        if (showHome) ...[
                          const SizedBox(width: _edge),
                          _ToolbarButton(
                            icon: Icons.home_outlined,
                            label: 'Home',
                            onPressed: onHome,
                          ),
                        ] else
                          const SizedBox(width: 12),
                        Expanded(
                          child: _AddressBar(
                            tab: tab,
                            slide: slide,
                            onTap: onEditAddress,
                            onLongPress: onAddressMenu,
                            onSiteInfo: onSiteInfo,
                          ),
                        ),
                        _ToolbarButton(
                          icon: Icons.add,
                          label: 'New tab',
                          onPressed: onNewTab,
                        ),
                        _TabCountButton(
                          count: tabCount,
                          onPressed: onTabs,
                          onLongPress: onTabsMenu,
                        ),
                        Builder(
                          builder: (context) => _ToolbarButton(
                            icon: Icons.more_vert,
                            label: 'Menu',
                            onPressed: () => onMenu(globalRectOf(context)),
                          ),
                        ),
                        const SizedBox(width: _edge),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: atBottom ? 0 : null,
                    bottom: atBottom ? null : 0,
                    child: Stack(
                      alignment: atBottom
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,
                      children: [
                        ColoredBox(
                          color: colors.divider.withValues(alpha: 0.6),
                          child: const SizedBox(
                            height: 0.6,
                            width: double.infinity,
                          ),
                        ),
                        MobileProgressBar(isLoading: tab.isLoadingNotifier),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _buttonWidth,
      height: 48,
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          child: Icon(icon, size: 24, color: context.mobile.text),
        ),
      ),
    );
  }
}

/// The square with the number of tabs in it.
class _TabCountButton extends StatelessWidget {
  const _TabCountButton({
    required this.count,
    required this.onPressed,
    required this.onLongPress,
  });

  final int count;
  final VoidCallback onPressed;
  final ValueChanged<Rect> onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _buttonWidth,
      height: 48,
      child: Semantics(
        button: true,
        label: 'Switch tabs, $count open',
        child: InkResponse(
          onTap: onPressed,
          onLongPress: () => onLongPress(globalRectOf(context)),
          radius: 24,
          child: Center(
            child: TabCountBadge(count: count, color: context.mobile.text),
          ),
        ),
      ),
    );
  }
}

class TabCountBadge extends StatelessWidget {
  const TabCountBadge({required this.count, required this.color, super.key});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // As Chrome does, past what fits.
    final text = count > 99 ? ':D' : '$count';
    return Container(
      width: 21,
      height: 21,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.8),
        borderRadius: BorderRadius.circular(5.5),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Text(
          text,
          key: ValueKey(text),
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: color,
            fontSize: text.length > 1 ? 10 : 11.5,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.tab,
    required this.slide,
    required this.onTap,
    required this.onLongPress,
    required this.onSiteInfo,
  });

  final LadybirdController tab;
  final ValueListenable<double> slide;
  final VoidCallback onTap;
  final ValueChanged<Rect> onLongPress;
  final VoidCallback onSiteInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Material(
      color: colors.field,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => onLongPress(globalRectOf(context)),
        child: SizedBox(
          height: kMobileAddressHeight,
          // The words move with a swipe between tabs; the field stays.
          child: ValueListenableBuilder<double>(
            valueListenable: slide,
            builder: (context, dx, child) {
              final width = MediaQuery.sizeOf(context).width;
              return Transform.translate(
                offset: Offset(dx * 0.35, 0),
                child: Opacity(
                  opacity: (1 - dx.abs() / width).clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: ValueListenableBuilder<String>(
              valueListenable: tab.urlNotifier,
              builder: (context, url, _) => _contents(context, url),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contents(BuildContext context, String url) {
    final colors = context.mobile;
    if (tab.isOnNewTabPage || url.isEmpty) {
      return Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search, size: 20, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Search or type URL',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(fontSize: 15, color: colors.textSecondary),
            ),
          ),
        ],
      );
    }

    final security = SiteSecurity.of(url);
    final address = displayAddress(url);
    final split = security.host.isEmpty
        ? -1
        : address.indexOf(RegExp(r'[/?#]'));
    final host = split < 0 ? address : address.substring(0, split);
    final rest = split < 0 ? '' : address.substring(split);

    return Row(
      children: [
        SizedBox(
          width: 40,
          height: kMobileAddressHeight,
          child: Semantics(
            button: true,
            label: 'Site information',
            child: InkResponse(
              onTap: onSiteInfo,
              radius: 20,
              child: Icon(
                switch (security.kind) {
                  SiteSecurityKind.insecure => Icons.warning_amber_rounded,
                  SiteSecurityKind.https ||
                  SiteSecurityKind.local => Icons.tune_rounded,
                  SiteSecurityKind.file => Icons.description_outlined,
                  SiteSecurityKind.extension => Icons.extension_outlined,
                  SiteSecurityKind.internal => Icons.info_outline,
                },
                size: 19,
                color: security.kind == SiteSecurityKind.insecure
                    ? colors.danger
                    : colors.textSecondary,
              ),
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: host,
                  style: TextStyle(color: colors.text),
                ),
                TextSpan(
                  text: rest,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        const SizedBox(width: 14),
      ],
    );
  }
}
