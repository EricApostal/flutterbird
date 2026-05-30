import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:flutterbird/features/frontend/abstraction/frontend_layer.dart';
import 'package:flutterbird/features/theme/base.dart';
import 'package:go_router/go_router.dart';

class FluentFrontendLayer extends FrontendLayer {
  const FluentFrontendLayer();

  @override
  FrontendFlavor get flavor => FrontendFlavor.fluent;

  @override
  Widget buildApp({
    required GoRouter routerConfig,
    required TransitionBuilder appBuilder,
  }) {
    return f.FluentApp.router(
      routerConfig: routerConfig,
      builder: (context, child) {
        final wrappedChild = appBuilder(context, child);
        final isDark = f.FluentTheme.of(context).brightness == Brightness.dark;
        final materialBridgeTheme = m.ThemeData(
          colorScheme: m.ColorScheme.fromSeed(
            brightness: isDark ? Brightness.dark : Brightness.light,
            seedColor: const Color.fromARGB(255, 0, 120, 212),
          ),
          textTheme: getBaseTextTheme(
            isDark
                ? m.ThemeData.dark().textTheme
                : m.ThemeData.light().textTheme,
          ),
          materialTapTargetSize: m.MaterialTapTargetSize.shrinkWrap,
        );

        return m.Theme(
          data: materialBridgeTheme,
          child: m.Material(color: m.Colors.transparent, child: wrappedChild),
        );
      },
      themeMode: f.ThemeMode.dark,
      theme: f.FluentThemeData(brightness: Brightness.light),
      darkTheme: f.FluentThemeData(brightness: Brightness.dark),
    );
  }

  @override
  Widget buildScaffold({required Widget body, Color? backgroundColor}) {
    return m.Scaffold(backgroundColor: backgroundColor, body: body);
  }

  @override
  Widget buildProgressIndicator() {
    return const f.ProgressRing();
  }

  @override
  Widget buildIconButton({
    required Widget icon,
    required VoidCallback? onPressed,
    String? tooltip,
    EdgeInsetsGeometry? padding,
    BoxConstraints? constraints,
  }) {
    Widget iconButton = f.IconButton(
      onPressed: onPressed,
      icon: icon,
      style: padding == null
          ? null
          : f.ButtonStyle(
              padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(padding),
            ),
    );

    if (constraints != null) {
      iconButton = ConstrainedBox(constraints: constraints, child: iconButton);
    }

    if (tooltip != null && tooltip.isNotEmpty) {
      return f.Tooltip(message: tooltip, child: iconButton);
    }

    return iconButton;
  }

  @override
  Widget buildFilledButton({
    required Widget child,
    required VoidCallback? onPressed,
    Color? backgroundColor,
  }) {
    return f.FilledButton(
      onPressed: onPressed,
      style: backgroundColor == null
          ? null
          : f.ButtonStyle(
              backgroundColor: WidgetStatePropertyAll<Color>(backgroundColor),
            ),
      child: child,
    );
  }

  @override
  Widget buildTooltip({required String message, required Widget child}) {
    return f.Tooltip(message: message, child: child);
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
    final bridgeTheme = m.Theme.of(context);
    final theme = f.FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = selected
        ? bridgeTheme.colorScheme.surfaceContainerHigh
        : m.Colors.transparent;
    final fallbackTitleColor = isDark
        ? const m.Color(0xFFF5F5F5)
        : const m.Color(0xFF1F1F1F);
    final titleColor = selected
        ? (theme.typography.body?.color ?? fallbackTitleColor)
        : theme.inactiveColor;

    return FrontendTabVisuals(
      backgroundColor: backgroundColor,
      titleColor: titleColor,
    );
  }

  @override
  Widget buildTabLoadingIndicator({required BuildContext context}) {
    return const SizedBox(width: 16, height: 16, child: f.ProgressRing());
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
    final theme = f.FluentTheme.of(context);

    return f.TextBox(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      placeholder: hintText,
      style: textStyle,
      placeholderStyle: theme.typography.body?.copyWith(
        fontSize: 13,
        color: theme.inactiveColor,
      ),
      decoration: WidgetStatePropertyAll<BoxDecoration>(
        BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focusNode.hasFocus ? theme.accentColor : theme.cardColor,
            width: 1,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildOmniboxSuggestionsSurface({
    required BuildContext context,
    required Widget child,
  }) {
    final bridgeTheme = m.Theme.of(context);
    final theme = f.FluentTheme.of(context);
    return f.Container(
      decoration: BoxDecoration(
        color: bridgeTheme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: child,
    );
  }

  @override
  Widget buildOmniboxSuggestionTile({
    required VoidCallback onPressed,
    required Widget child,
  }) {
    return f.HoverButton(
      onPressed: onPressed,
      builder: (context, states) => child,
    );
  }
}
