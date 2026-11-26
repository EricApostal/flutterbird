import 'package:flutter/widgets.dart';

/// What the pages drawn inside the phone's browser screen can ask of it.
class MobileBrowserScope extends InheritedWidget {
  const MobileBrowserScope({
    required this.editAddress,
    required super.child,
    super.key,
  });

  /// Opens the address bar to be typed in.
  final VoidCallback editAddress;

  static MobileBrowserScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MobileBrowserScope>();

  @override
  bool updateShouldNotify(MobileBrowserScope oldWidget) => false;
}
