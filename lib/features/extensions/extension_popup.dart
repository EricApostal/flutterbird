import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:ladybird/ladybird.dart';

/// An extension's popup: its page, in a view that lives as long as the popup
/// is open.
class ExtensionPopup extends StatefulWidget {
  const ExtensionPopup({required this.url, required this.onClose, super.key});

  final String url;
  final VoidCallback onClose;

  @override
  State<ExtensionPopup> createState() => _ExtensionPopupState();
}

class _ExtensionPopupState extends State<ExtensionPopup> {
  late final LadybirdController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LadybirdController();
    _controller.navigate(widget.url);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 6,
      color: omniboxSurfaceColor(theme),
      borderRadius: BorderRadius.circular(kOmniboxFieldRadius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 380,
        height: 520,
        child: LadybirdView(controller: _controller),
      ),
    );
  }
}
