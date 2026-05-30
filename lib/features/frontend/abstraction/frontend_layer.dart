import 'package:flutter/widgets.dart';
import 'package:flutterbird/features/frontend/layers/fluent_frontend_layer.dart';
import 'package:flutterbird/features/frontend/layers/material_frontend_layer.dart';
import 'package:go_router/go_router.dart';

enum FrontendFlavor { material, fluent }

const String _kFrontendEnvironment = String.fromEnvironment(
  'FLUTTERBIRD_FRONTEND',
  defaultValue: 'fluent',
);

FrontendFlavor _defaultFrontendFlavorFromEnvironment() {
  switch (_kFrontendEnvironment.trim().toLowerCase()) {
    case 'fluent':
      return FrontendFlavor.fluent;
    case 'material':
    default:
      return FrontendFlavor.material;
  }
}

FrontendLayer resolveFrontendLayer({FrontendFlavor? flavor}) {
  final activeFlavor = flavor ?? _defaultFrontendFlavorFromEnvironment();
  return switch (activeFlavor) {
    FrontendFlavor.material => const MaterialFrontendLayer(),
    FrontendFlavor.fluent => const FluentFrontendLayer(),
  };
}

class FrontendTabVisuals {
  final Color backgroundColor;
  final Color titleColor;

  const FrontendTabVisuals({
    required this.backgroundColor,
    required this.titleColor,
  });
}

abstract class FrontendLayer {
  const FrontendLayer();

  FrontendFlavor get flavor;

  Widget buildApp({
    required GoRouter routerConfig,
    required TransitionBuilder appBuilder,
  });

  Widget buildScaffold({required Widget body, Color? backgroundColor});

  Widget buildProgressIndicator();

  Widget buildIconButton({
    required Widget icon,
    required VoidCallback? onPressed,
    String? tooltip,
    EdgeInsetsGeometry? padding,
    BoxConstraints? constraints,
  });

  Widget buildFilledButton({
    required Widget child,
    required VoidCallback? onPressed,
    Color? backgroundColor,
  });

  Widget buildTooltip({required String message, required Widget child});

  Widget buildTabSurface({
    required BorderRadius borderRadius,
    required VoidCallback onPressed,
    required Widget child,
  });

  FrontendTabVisuals resolveTabVisuals({
    required BuildContext context,
    required bool selected,
    required bool sidebarVariant,
  });

  Widget buildTabLoadingIndicator({required BuildContext context});

  Widget buildOmniboxTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onSubmitted,
    required String hintText,
    required TextStyle? textStyle,
  });

  Widget buildOmniboxSuggestionsSurface({
    required BuildContext context,
    required Widget child,
  });

  Widget buildOmniboxSuggestionTile({
    required VoidCallback onPressed,
    required Widget child,
  });
}

class FrontendScope extends InheritedWidget {
  final FrontendLayer layer;

  const FrontendScope({super.key, required this.layer, required super.child});

  static FrontendLayer of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FrontendScope>();
    if (scope != null) {
      return scope.layer;
    }
    return resolveFrontendLayer();
  }

  @override
  bool updateShouldNotify(covariant FrontendScope oldWidget) {
    return oldWidget.layer.flavor != layer.flavor;
  }
}
