import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/router/components/navigation_scope.dart';
import 'package:go_router/go_router.dart';

final routerController = GoRouter(
  initialLocation: "/browser",
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return NavigationScope(child: child);
      },
      routes: [
        GoRoute(
          path: "/browser",
          builder: (context, state) {
            return BrowserWindow();
          },
        ),
      ],
    ),
  ],
);
