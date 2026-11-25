/// Where new windows go.
library;

import 'dart:math' as math;

import 'package:bird_window/bird_window.dart';

abstract final class WindowPlacement {
  static const ScreenSize defaultSize = ScreenSize(1200, 800);
  static const ScreenSize minimumSize = ScreenSize(800, 600);

  static const ScreenSize defaultPopupSize = ScreenSize(500, 650);
  static const ScreenSize minimumPopupSize = ScreenSize(300, 200);

  static const double _cascadeStep = 28;

  /// The first window: in the middle of the screen.
  static ScreenRect centered(
    ScreenRect screen, [
    ScreenSize size = defaultSize,
  ]) {
    final width = math.min(size.width, screen.width);
    final height = math.min(size.height, screen.height);
    return ScreenRect(
      screen.left + (screen.width - width) / 2,
      screen.top + (screen.height - height) / 2,
      width,
      height,
    );
  }

  /// A window opened from another: the same size, a step down and to the right.
  static ScreenRect cascaded(ScreenRect from, ScreenRect screen) => ScreenRect(
    from.left + _cascadeStep,
    from.top + _cascadeStep,
    from.width,
    from.height,
  ).keepInside(screen);

  /// The size of the window a tab is torn off into: that of the window it came
  /// from, unless that one fills the screen, when a new one the same size would
  /// hide everything there is to drag the tab to.
  static ScreenSize tearOffSize(ScreenRect from, ScreenRect screen) {
    final fills =
        from.width >= screen.width * 0.95 &&
        from.height >= screen.height * 0.95;
    if (!fills) return from.size;
    return ScreenSize(
      math.max(minimumSize.width, screen.width * 0.7),
      math.max(minimumSize.height, screen.height * 0.8),
    );
  }

  /// A popup, over the middle of the window that opened it.
  ///
  /// [width] and [height] are what the page asked for, which is the size of
  /// the page itself; [chromeHeight] is what the window adds above it.
  ///
  /// The `left` and `top` a page asks for are not used. Pages work them out
  /// from where their own window is on screen, which the engine is not told
  /// yet, so they would put the popup somewhere unrelated.
  static ScreenRect popup({
    required ScreenRect opener,
    required ScreenRect screen,
    required double chromeHeight,
    int? width,
    int? height,
  }) {
    final requestedWidth = (width != null && width > 0)
        ? width.toDouble()
        : defaultPopupSize.width;
    final requestedHeight = (height != null && height > 0)
        ? height.toDouble()
        : defaultPopupSize.height;

    final outerWidth = math.max(requestedWidth, minimumPopupSize.width);
    final outerHeight =
        math.max(requestedHeight, minimumPopupSize.height) + chromeHeight;

    return ScreenRect(
      opener.left + (opener.width - outerWidth) / 2,
      opener.top + (opener.height - outerHeight) / 2,
      outerWidth,
      outerHeight,
    ).keepInside(screen);
  }
}
