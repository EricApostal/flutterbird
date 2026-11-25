import 'package:flutter/widgets.dart';

/// Says which browser window the widgets below it are in.
///
/// It goes above each window's `MaterialApp`, so that dialogs and overlays,
/// which hang off the app's navigator, know their window too.
class BrowserWindowScope extends InheritedWidget {
  const BrowserWindowScope({
    required this.windowId,
    required super.child,
    super.key,
  });

  final int windowId;

  static int of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<BrowserWindowScope>();
    assert(scope != null, 'There is no BrowserWindowScope above this widget');
    return scope!.windowId;
  }

  // A widget never moves from one window's scope to another's: the tab that
  // moves between windows gets new widgets.
  @override
  bool updateShouldNotify(BrowserWindowScope oldWidget) =>
      windowId != oldWidget.windowId;
}
