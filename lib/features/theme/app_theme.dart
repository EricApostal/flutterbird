import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/theme/base.dart';

/// Pages change at once, as a browser's do.
class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

const PageTransitionsTheme _noPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.fuchsia: _NoTransition(),
    TargetPlatform.iOS: _NoTransition(),
    TargetPlatform.linux: _NoTransition(),
    TargetPlatform.macOS: _NoTransition(),
    TargetPlatform.windows: _NoTransition(),
  },
);

/// The themes of the Android app, which is a Material one. The desktop
/// interface is drawn with bird_ui instead.
ThemeData birdDarkTheme() => ThemeData(
  pageTransitionsTheme: _noPageTransitions,
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: const Color.fromARGB(255, 53, 111, 227),
  ),
  textTheme: getBaseTextTheme(ThemeData.dark().textTheme),
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

ThemeData birdLightTheme() => ThemeData(
  pageTransitionsTheme: _noPageTransitions,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color.fromARGB(255, 35, 141, 255),
  ),
  textTheme: getBaseTextTheme(ThemeData.light().textTheme),
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
