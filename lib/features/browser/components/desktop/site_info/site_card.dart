import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_style.dart';

/// The panel that hangs from the site information button.
class SiteCard extends StatelessWidget {
  const SiteCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: omniboxSurfaceColor(Theme.of(context)),
      borderRadius: BorderRadius.circular(kOmniboxFieldRadius),
      child: SizedBox(
        width: 340,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );
  }
}
