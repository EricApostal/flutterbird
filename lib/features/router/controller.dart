import 'package:rubisco_browser/features/browser/screens/browser.dart';
import 'package:rubisco_browser/features/browser/screens/loading.dart';
import 'package:rubisco_browser/features/mobile/tabs/mobile_tab_switcher.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show Rect;

// NB: The tab and the tab switcher are routes of their own, not children of
// `/browser`. A child route is shown over its parent, so `/browser/tab/1` built
// the stack [loading screen, tab], and going back from a tab landed on the
// loading screen's spinner. `/browser` is only where the app starts: it sends
// the user to the first tab, which then is the bottom of the stack, so going back
// from it leaves the app, as it does in a browser.
final routerController = GoRouter(
  initialLocation: "/browser",
  routes: [
    GoRoute(
      path: "/browser",
      builder: (context, state) {
        return BrowserLoadingScreen();
      },
    ),
    GoRoute(
      path: "/browser/mobile_tabs",
      // The switcher animates itself, from the route's animation: the page
      // shrinks into its card, and the chosen card grows into the page.
      pageBuilder: (context, state) {
        final page = switch (state.extra) {
          [num left, num top, num width, num height] => Rect.fromLTWH(
            left.toDouble(),
            top.toDouble(),
            width.toDouble(),
            height.toDouble(),
          ),
          _ => null,
        };
        return CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondary, child) => child,
          child: MobileTabSwitcher(pageRect: page),
        );
      },
    ),
    GoRoute(
      // TODO: Some tabs will probably be flutter based to some extent,
      // so at some point I should provide some sort of uuid abstraction
      path: "/browser/tab/:viewId",
      // Every tab shares this route's page, so a switch updates it in place.
      // It is never a page that pushes, so it never animates in or out.
      pageBuilder: (context, state) {
        final viewId = int.parse(state.pathParameters["viewId"] as String);
        return NoTransitionPage<void>(
          key: state.pageKey,
          child: BrowserWindowScreen(viewId: viewId),
        );
      },
    ),
  ],
);
