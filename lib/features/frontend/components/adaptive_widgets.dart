import 'package:flutter/widgets.dart';
import 'package:flutterbird/features/frontend/abstraction/frontend_layer.dart';

class FrontendScaffold extends StatelessWidget {
  final Widget body;
  final Color? backgroundColor;

  const FrontendScaffold({super.key, required this.body, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildScaffold(body: body, backgroundColor: backgroundColor);
  }
}

class FrontendProgressIndicator extends StatelessWidget {
  const FrontendProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildProgressIndicator();
  }
}

class FrontendIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  const FrontendIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.padding,
    this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildIconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      padding: padding,
      constraints: constraints,
    );
  }
}

class FrontendFilledButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color? backgroundColor;

  const FrontendFilledButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildFilledButton(
      child: child,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
    );
  }
}

class FrontendTooltip extends StatelessWidget {
  final String message;
  final Widget child;

  const FrontendTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildTooltip(message: message, child: child);
  }
}

class FrontendTabSurface extends StatelessWidget {
  final BorderRadius borderRadius;
  final VoidCallback onPressed;
  final Widget child;

  const FrontendTabSurface({
    super.key,
    required this.borderRadius,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildTabSurface(
      borderRadius: borderRadius,
      onPressed: onPressed,
      child: child,
    );
  }
}

class FrontendTabLoadingIndicator extends StatelessWidget {
  const FrontendTabLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildTabLoadingIndicator(context: context);
  }
}

class FrontendOmniboxTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final String hintText;
  final TextStyle? textStyle;

  const FrontendOmniboxTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.hintText = 'Search',
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildOmniboxTextField(
      context: context,
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      hintText: hintText,
      textStyle: textStyle,
    );
  }
}

class FrontendOmniboxSuggestionsSurface extends StatelessWidget {
  final Widget child;

  const FrontendOmniboxSuggestionsSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildOmniboxSuggestionsSurface(
      context: context,
      child: child,
    );
  }
}

class FrontendOmniboxSuggestionTile extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;

  const FrontendOmniboxSuggestionTile({
    super.key,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    return frontend.buildOmniboxSuggestionTile(
      onPressed: onPressed,
      child: child,
    );
  }
}
