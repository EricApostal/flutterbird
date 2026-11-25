import 'package:flutter/material.dart';
import 'package:flutterbird/features/theme/base.dart';
import 'package:go_transitions/go_transitions.dart';

const PageTransitionsTheme _noPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.fuchsia: GoTransitions.none,
    TargetPlatform.iOS: GoTransitions.none,
    TargetPlatform.linux: GoTransitions.none,
    TargetPlatform.macOS: GoTransitions.none,
    TargetPlatform.windows: GoTransitions.none,
  },
);

/// The app's themes, the same in every window.
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
