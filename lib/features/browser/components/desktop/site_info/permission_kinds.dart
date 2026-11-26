import 'package:bird_ui/bird_ui.dart';

/// How a permission of the engine is shown.
class PermissionKind {
  const PermissionKind(this.label, this.action, this.glyph);

  final String label;

  /// What a site that has it can do, to finish "wants to ...".
  final String action;
  final BirdGlyph glyph;

  static PermissionKind of(String name) => switch (name) {
    'geolocation' => const PermissionKind(
      'Location',
      'know your location',
      BirdGlyph.location,
    ),
    'microphone' => const PermissionKind(
      'Microphone',
      'use your microphone',
      BirdGlyph.microphone,
    ),
    'notifications' => const PermissionKind(
      'Notifications',
      'send you notifications',
      BirdGlyph.bell,
    ),
    _ => PermissionKind(name, 'use "$name"', BirdGlyph.shield),
  };
}
