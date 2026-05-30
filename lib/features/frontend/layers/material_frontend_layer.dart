import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:flutterbird/features/frontend/abstraction/frontend_layer.dart';
import 'package:flutterbird/features/theme/base.dart';
import 'package:go_router/go_router.dart';
import 'package:go_transitions/go_transitions.dart';

class MaterialFrontendLayer extends FrontendLayer {
  const MaterialFrontendLayer();

  @override
  FrontendFlavor get flavor => FrontendFlavor.material;

  @override
  Widget buildApp({
    required GoRouter routerConfig,
    required TransitionBuilder appBuilder,
  }) {
    final pageTransition = const m.PageTransitionsTheme(
      builders: {
        TargetPlatform.fuchsia: GoTransitions.none,
        TargetPlatform.iOS: GoTransitions.none,
        TargetPlatform.linux: GoTransitions.none,
        TargetPlatform.macOS: GoTransitions.none,
        TargetPlatform.windows: GoTransitions.none,
      },
    );

    return m.MaterialApp.router(
      routerConfig: routerConfig,
      builder: appBuilder,
      themeMode: m.ThemeMode.dark,
      darkTheme: m.ThemeData(
        pageTransitionsTheme: pageTransition,
        colorScheme: m.ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color.fromARGB(255, 35, 174, 255),
        ),
        textTheme: getBaseTextTheme(m.ThemeData.dark().textTheme),
        materialTapTargetSize: m.MaterialTapTargetSize.shrinkWrap,
      ),
      theme: m.ThemeData(
        pageTransitionsTheme: pageTransition,
        colorScheme: m.ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 35, 141, 255),
        ),
        textTheme: getBaseTextTheme(m.ThemeData.light().textTheme),
        materialTapTargetSize: m.MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  @override
  Widget buildScaffold({required Widget body, Color? backgroundColor}) {
    return m.Scaffold(backgroundColor: backgroundColor, body: body);
  }

  @override
  Widget buildProgressIndicator() {
    return const m.CircularProgressIndicator.adaptive();
  }

  @override
  Widget buildIconButton({
    required Widget icon,
    required VoidCallback? onPressed,
    String? tooltip,
    EdgeInsetsGeometry? padding,
    BoxConstraints? constraints,
  }) {
    return m.IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: padding,
      constraints: constraints,
      icon: icon,
    );
  }

  @override
  Widget buildFilledButton({
    required Widget child,
    required VoidCallback? onPressed,
    Color? backgroundColor,
  }) {
    return m.FilledButton(
      onPressed: onPressed,
      style: backgroundColor == null
          ? null
          : m.FilledButton.styleFrom(backgroundColor: backgroundColor),
      child: child,
    );
  }

  @override
  Widget buildTooltip({required String message, required Widget child}) {
    return m.Tooltip(message: message, child: child);
  }

  @override
  Widget buildTabSurface({
    required BorderRadius borderRadius,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    return m.Material(
      borderRadius: borderRadius,
      color: m.Colors.transparent,
      child: m.InkWell(
        borderRadius: borderRadius,
        onTap: onPressed,
        child: child,
      ),
    );
  }

  @override
  FrontendTabVisuals resolveTabVisuals({
    required BuildContext context,
    required bool selected,
    required bool sidebarVariant,
  }) {
    final theme = m.Theme.of(context);
    final backgroundColor = selected
        ? theme.colorScheme.surfaceContainerHighest
        : sidebarVariant
        ? theme.colorScheme.surfaceContainerLow
        : m.Colors.transparent;
    final titleColor = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return FrontendTabVisuals(
      backgroundColor: backgroundColor,
      titleColor: titleColor,
    );
  }

  @override
  Widget buildTabLoadingIndicator({required BuildContext context}) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: m.CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  Widget buildOmniboxTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onSubmitted,
    required String hintText,
    required TextStyle? textStyle,
  }) {
    final theme = m.Theme.of(context);
    const radius = 8.0;

    return m.TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      style: textStyle,
      decoration: m.InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: theme.colorScheme.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withAlpha(150),
        ),
        enabledBorder: m.OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: m.BorderSide(color: theme.colorScheme.surface, width: 1),
        ),
        focusedBorder: m.OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: m.BorderSide(color: theme.colorScheme.primary, width: 1),
        ),
        errorBorder: m.OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: m.BorderSide(color: theme.colorScheme.error, width: 1),
        ),
        focusedErrorBorder: m.OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: m.BorderSide(color: theme.colorScheme.error, width: 1),
        ),
      ),
    );
  }

  @override
  Widget buildOmniboxSuggestionsSurface({
    required BuildContext context,
    required Widget child,
  }) {
    final theme = m.Theme.of(context);
    return m.Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: child,
    );
  }

  @override
  Widget buildOmniboxSuggestionTile({
    required VoidCallback onPressed,
    required Widget child,
  }) {
    return m.InkWell(onTap: onPressed, child: child);
  }
}
