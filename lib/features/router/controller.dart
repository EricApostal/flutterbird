import 'package:flutterbird/features/browser/screens/browser.dart';
import 'package:flutterbird/features/browser/screens/loading.dart';
import 'package:go_router/go_router.dart';

final routerController = GoRouter(
  initialLocation: "/browser",
  routes: [
    GoRoute(
      path: "/browser",
      builder: (context, state) {
        return BrowserLoadingScreen();
      },
      routes: [
        GoRoute(
          // TODO: Some tabs will probably be flutter based to some extent,
          // so at some point I should provide some sort of uuid abstraction
          path: "tab/:viewId",
          builder: (context, state) {
            final viewId = int.parse(state.pathParameters["viewId"] as String);
            return BrowserWindowScreen(viewId: viewId);
          },
        ),
      ],
    ),
  ],
);
