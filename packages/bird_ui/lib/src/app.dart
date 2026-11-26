import 'package:flutter/widgets.dart';

import 'scroll.dart';
import 'theme.dart';

enum BirdThemeMode { system, light, dark }

/// The root of a window: what [WidgetsApp] gives (navigation, overlays,
/// editing keys, focus traversal) in the browser's colours and type.
class BirdApp extends StatelessWidget {
  const BirdApp({super.key, required Widget this.home, this.themeMode = BirdThemeMode.system, this.title = ''})
    : routerConfig = null,
      builder = null;

  const BirdApp.router({
    super.key,
    required RouterConfig<Object> this.routerConfig,
    this.themeMode = BirdThemeMode.system,
    this.title = '',
    this.builder,
  }) : home = null;

  final Widget? home;
  final RouterConfig<Object>? routerConfig;
  final BirdThemeMode themeMode;
  final String title;

  /// Wraps what the router shows, inside the theme.
  final TransitionBuilder? builder;

  Widget _wrap(BuildContext context, Widget? child) {
    final colors = BirdColors.forBrightness(switch (themeMode) {
      BirdThemeMode.light => Brightness.light,
      BirdThemeMode.dark => Brightness.dark,
      BirdThemeMode.system => MediaQuery.platformBrightnessOf(context),
    });
    return BirdTheme(
      colors: colors,
      child: Builder(
        builder: (context) => DefaultTextStyle(
          style: context.birdText(),
          child: IconTheme(
            data: IconThemeData(color: colors.icon, size: 16),
            child: DefaultSelectionStyle(
              cursorColor: colors.text,
              selectionColor: colors.textSelection,
              child: ScrollConfiguration(
                behavior: const BirdScrollBehavior(),
                child: builder?.call(context, child) ?? child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF0061E0);
    final routerConfig = this.routerConfig;
    if (routerConfig != null) {
      return WidgetsApp.router(
        routerConfig: routerConfig,
        color: color,
        title: title,
        debugShowCheckedModeBanner: false,
        builder: _wrap,
      );
    }
    return WidgetsApp(
      color: color,
      title: title,
      debugShowCheckedModeBanner: false,
      builder: _wrap,
      home: home,
      // Desktop windows change pages without sliding them about.
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => builder(context),
      ),
    );
  }
}
