import 'package:flutter/material.dart';

/// Shared visual constants so the suggestions panel reads as a continuous
/// extension of the search field rather than a separate floating dropdown.
const double kOmniboxFieldRadius = 10.0;

/// The corners of the one shape the field and its suggestions make when open.
const double kOmniboxPanelRadius = 12.0;

Color omniboxSurfaceColor(ThemeData theme) {
  return Color.lerp(Colors.black, theme.colorScheme.primaryContainer, 0.5)!;
}
