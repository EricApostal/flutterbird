import 'package:flutter/material.dart';

/// How a permission of the engine is shown.
class PermissionKind {
  const PermissionKind(this.label, this.action, this.icon);

  final String label;

  /// What a site that has it can do, to finish "wants to ...".
  final String action;
  final IconData icon;

  static PermissionKind of(String name) => switch (name) {
    'geolocation' => const PermissionKind(
      'Location',
      'know your location',
      Icons.location_on_outlined,
    ),
    'microphone' => const PermissionKind(
      'Microphone',
      'use your microphone',
      Icons.mic_none,
    ),
    'notifications' => const PermissionKind(
      'Notifications',
      'send you notifications',
      Icons.notifications_none,
    ),
    _ => PermissionKind(name, 'use "$name"', Icons.shield_outlined),
  };
}
