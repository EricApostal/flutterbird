import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';

/// The panel that hangs from the site information button.
class SiteCard extends StatelessWidget {
  const SiteCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BirdPanel(
      width: 340,
      padding: const EdgeInsets.all(14),
      // A long list of permissions in a short window.
      child: SingleChildScrollView(child: child),
    );
  }
}
