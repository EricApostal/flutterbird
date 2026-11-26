import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Desktop scrolling: thin bars, and no glow or bounce.
class BirdScrollBehavior extends ScrollBehavior {
  const BirdScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) return child;
    return RawScrollbar(
      controller: details.controller,
      thickness: 7,
      radius: const Radius.circular(4),
      padding: const EdgeInsets.all(1),
      thumbColor: context.bird.textSecondary.withValues(alpha: 0.45),
      fadeDuration: const Duration(milliseconds: 200),
      timeToFade: const Duration(milliseconds: 800),
      child: child,
    );
  }
}
