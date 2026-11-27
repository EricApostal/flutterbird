import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

/// An extension's icon: the one its button was given, where there is a
/// [state], and its own otherwise, with the button's badge.
class MobileExtensionIcon extends StatelessWidget {
  const MobileExtensionIcon({
    required this.service,
    required this.extension,
    this.state,
    this.size = 24,
    super.key,
  });

  final ExtensionService service;
  final InstalledExtension extension;
  final ActionState? state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.extension_outlined,
      size: size,
      color: context.mobile.textSecondary,
    );
    final path = state?.iconPath ?? extension.iconPath;
    final icon = path == null
        ? fallback
        : Image.file(
            File('${service.registry.directoryFor(extension).path}/$path'),
            width: size,
            height: size,
            // An icon Flutter cannot draw, such as an SVG.
            errorBuilder: (_, _, _) => fallback,
          );

    final badge = state?.badgeText ?? '';
    final colour = state?.badgeBackground;
    final background = colour == null
        ? null
        : Color.fromARGB(colour[3], colour[0], colour[1], colour[2]);
    return Badge(
      isLabelVisible: badge.isNotEmpty,
      label: Text(badge),
      backgroundColor: background,
      textColor: background == null
          ? null
          : (background.computeLuminance() > 0.45
                ? Colors.black
                : Colors.white),
      child: icon,
    );
  }
}
