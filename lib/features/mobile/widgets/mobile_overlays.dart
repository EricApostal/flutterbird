import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

/// A full screen of the app's own, such as settings or history, coming in from
/// the side as Android's screens do.
Route<T> mobilePageRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 360),
  reverseTransitionDuration: const Duration(milliseconds: 280),
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final entering = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final covered = secondaryAnimation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.12, 0),
      ).animate(covered),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.22, 0),
          end: Offset.zero,
        ).animate(entering),
        child: FadeTransition(opacity: entering, child: child),
      ),
    );
  },
);

Future<T?> pushMobilePage<T>(BuildContext context, Widget page) =>
    Navigator.of(context, rootNavigator: true).push(mobilePageRoute<T>(page));

/// Takes away every screen, menu and sheet over the browser, leaving the
/// router's own pages. They hang off the router's page, which stays as it is
/// when another tab is shown, so going to a tab does not close them.
void closeMobileOverlays(NavigatorState navigator) {
  navigator.popUntil((route) => route.settings is Page);
}

/// A short note at the bottom of the screen, with something to do about it.
void showMobileSnack(
  ScaffoldMessengerState? messenger,
  String message, {
  String? action,
  VoidCallback? onAction,
  double bottomGap = 72,
  Duration duration = const Duration(seconds: 4),
}) {
  if (messenger == null || !messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        duration: duration,
        // One with a button would otherwise stay until it was pressed.
        persist: false,
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottomGap),
        action: action == null
            ? null
            : SnackBarAction(label: action, onPressed: onAction ?? () {}),
      ),
    );
}

/// Where [context]'s widget is on the screen, for a menu to open from.
Rect globalRectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// A menu that grows out of the button or the spot that opened it.
Future<T?> showMobileMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required WidgetBuilder builder,
  double width = 240,
}) {
  final screen = MediaQuery.sizeOf(context);
  final origin = Alignment(
    (anchor.center.dx / screen.width * 2 - 1).clamp(-1.0, 1.0),
    (anchor.center.dy / screen.height * 2 - 1).clamp(-1.0, 1.0),
  );

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      final media = MediaQuery.of(context);
      return CustomSingleChildLayout(
        delegate: _MenuLayout(
          anchor: anchor,
          padding: media.viewPadding.copyWith(
            bottom: math.max(media.viewPadding.bottom, media.viewInsets.bottom),
          ),
          width: width,
        ),
        child: Material(
          color: context.mobile.menu,
          elevation: 8,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: builder(context),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: origin,
          scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({
    required this.anchor,
    required this.padding,
    required this.width,
  });

  final Rect anchor;
  final EdgeInsets padding;
  final double width;

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final widest = math.max(0.0, constraints.maxWidth - 2 * _margin);
    final menuWidth = math.min(width, widest);
    return BoxConstraints(
      minWidth: menuWidth,
      maxWidth: menuWidth,
      maxHeight: math.max(
        0.0,
        constraints.maxHeight - padding.vertical - 2 * _margin,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final opensUp = anchor.center.dy > size.height / 2;
    final alignsRight = anchor.center.dx > size.width / 2;
    final x = alignsRight ? anchor.right - childSize.width : anchor.left;
    final y = opensUp ? anchor.bottom - childSize.height : anchor.top;

    double within(double value, double low, double high) =>
        high < low ? low : value.clamp(low, high);
    return Offset(
      within(x, _margin, size.width - childSize.width - _margin),
      within(
        y,
        padding.top + _margin,
        size.height - padding.bottom - childSize.height - _margin,
      ),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) =>
      old.anchor != anchor || old.padding != padding || old.width != width;
}

/// One line of a menu.
class MobileMenuRow extends StatelessWidget {
  const MobileMenuRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.checked = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final color = onTap == null
        ? colors.textSecondary.withValues(alpha: 0.5)
        : colors.text;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: color),
                ),
              ),
              if (checked) Icon(Icons.check, size: 20, color: colors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sheet from the bottom of the screen, with a handle to drag it away by.
Future<T?> showMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => Padding(
    // Above the keyboard, and above the system's gesture bar.
    padding: EdgeInsets.only(
      bottom: math.max(
        MediaQuery.viewInsetsOf(context).bottom,
        MediaQuery.viewPaddingOf(context).bottom,
      ),
    ),
    child: SingleChildScrollView(child: builder(context)),
  ),
);

/// Asks before doing what cannot be undone.
Future<bool> confirmMobileAction({
  required BuildContext context,
  required String title,
  required String message,
  required String confirm,
}) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return agreed ?? false;
}
