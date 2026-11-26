import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'button.dart';
import 'popover.dart';
import 'text_field.dart';
import 'theme.dart';

/// Shows a dialog over the window [context] is in, dimming the rest of it.
/// Escape, and a press outside where [barrierDismissible], answer null.
Future<T?> showBirdDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  final colors = context.bird;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible ? 'Dismiss' : null,
    barrierColor: colors.scrim,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, _) {
      final dialog = SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          // A little above the middle, where the eye is.
          child: Align(alignment: const Alignment(0, -0.35), child: builder(context)),
        ),
      );
      // The dialog wears what it was asked for from, not what the navigator
      // is under.
      return BirdTheme(colors: colors, child: dialog);
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.97, end: 1).animate(curved), child: child),
      );
    },
  );
}

/// A button of a [BirdDialog].
@immutable
class BirdDialogAction {
  const BirdDialogAction(
    this.label, {
    required this.onPressed,
    this.kind = BirdButtonKind.secondary,
    this.isDefault = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BirdButtonKind kind;

  /// What Return does while no other button has the keyboard. Leave it unset
  /// for what must not happen by a stray key, such as granting something.
  final bool isDefault;
  final bool autofocus;
}

/// A question or a form: a title, what it is about, and buttons along the
/// bottom right, in the order macOS has them, with the one that goes ahead
/// last.
class BirdDialog extends StatefulWidget {
  const BirdDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.leading,
    this.footer,
    required this.actions,
    this.width = 440,
  });

  final String title;
  final String? message;
  final Widget? content;

  /// An icon beside the title.
  final Widget? leading;

  /// Something at the bottom left, across from the buttons.
  final Widget? footer;
  final List<BirdDialogAction> actions;
  final double width;

  @override
  State<BirdDialog> createState() => _BirdDialogState();
}

class _BirdDialogState extends State<BirdDialog> {
  final FocusNode _focus = FocusNode(debugLabel: 'dialog');

  @override
  void initState() {
    super.initState();
    // Takes the keyboard where nothing inside asks for it, so that Escape
    // works from the start. Whatever does ask has had it by the next turn of
    // the event loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // In a field, Return is the field's: the platform submits it, and doing
      // the default as well would answer twice.
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.findAncestorStateOfType<EditableTextState>() != null) return KeyEventResult.ignored;
      final action = widget.actions.where((action) => action.isDefault).firstOrNull;
      if (action?.onPressed == null) return KeyEventResult.ignored;
      action!.onPressed!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) => _key(context, event),
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: widget.title,
        child: BirdPanel(
          radius: BirdRadius.dialog,
          constraints: BoxConstraints(maxWidth: widget.width),
          child: SizedBox(
            width: widget.width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 12)],
                      Expanded(
                        child: Text(
                          widget.title,
                          style: context.birdText(size: BirdTextSize.headline, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (widget.message != null || widget.content != null) ...[
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          // Room for focus rings, which a scroll view clips.
                          padding: const EdgeInsets.all(2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.message != null)
                                Text(widget.message!, style: context.birdText(color: colors.textSecondary, height: 1.4)),
                              if (widget.message != null && widget.content != null) const SizedBox(height: 12),
                              ?widget.content,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Align(alignment: Alignment.centerLeft, child: widget.footer)),
                      for (final action in widget.actions) ...[
                        const SizedBox(width: 4),
                        BirdButton(
                          action.label,
                          kind: action.kind,
                          autofocus: action.autofocus,
                          onPressed: action.onPressed,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Says something, and waits to be told it was heard.
Future<void> showBirdAlert(BuildContext context, {required String title, String? message, String okLabel = 'OK'}) {
  return showBirdDialog<void>(
    context: context,
    builder: (context) => BirdDialog(
      title: title,
      message: message,
      actions: [
        BirdDialogAction(
          okLabel,
          kind: BirdButtonKind.primary,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// Asks yes or no. Where what is confirmed is [destructive], Return does not
/// do it, and the keyboard starts on the way out.
Future<bool> showBirdConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final answer = await showBirdDialog<bool>(
    context: context,
    builder: (context) => BirdDialog(
      title: title,
      message: message,
      actions: [
        BirdDialogAction(cancelLabel, autofocus: destructive, onPressed: () => Navigator.of(context).pop(false)),
        BirdDialogAction(
          confirmLabel,
          kind: destructive ? BirdButtonKind.danger : BirdButtonKind.primary,
          isDefault: !destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Asks for a line of text. Null if the user would not give one.
Future<String?> showBirdPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String initialValue = '',
  String placeholder = '',
  String confirmLabel = 'OK',
  bool obscureText = false,
}) {
  return showBirdDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(
      title: title,
      message: message,
      initialValue: initialValue,
      placeholder: placeholder,
      confirmLabel: confirmLabel,
      obscureText: obscureText,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.message,
    required this.initialValue,
    required this.placeholder,
    required this.confirmLabel,
    required this.obscureText,
  });

  final String title;
  final String? message;
  final String initialValue;
  final String placeholder;
  final String confirmLabel;
  final bool obscureText;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initialValue)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialValue.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(_text.text);

  @override
  Widget build(BuildContext context) => BirdDialog(
    title: widget.title,
    message: widget.message,
    content: BirdTextField(
      controller: _text,
      placeholder: widget.placeholder,
      obscureText: widget.obscureText,
      autofocus: true,
      keepFocusOnSubmit: true,
      onSubmitted: (_) => _confirm(),
    ),
    actions: [
      BirdDialogAction('Cancel', onPressed: () => Navigator.of(context).pop()),
      BirdDialogAction(widget.confirmLabel, kind: BirdButtonKind.primary, onPressed: _confirm),
    ],
  );
}
