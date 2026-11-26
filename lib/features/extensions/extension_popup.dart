import 'dart:async';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter/material.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:ladybird/ladybird.dart';

/// The most room a popup may take, as in Firefox.
const _maxPopupSize = Size(800, 600);
const _minPopupSize = Size(120, 60);

/// An extension's popup: its page, in a view that lives as long as the popup
/// is open. The popup is as big as its content, up to a limit.
class ExtensionPopup extends StatefulWidget {
  const ExtensionPopup({
    required this.url,
    required this.contentSizes,
    required this.onClose,
    super.key,
  });

  final String url;

  /// How much room the content of extensions' pages takes, from the host.
  final Stream<ExtensionContentSize> contentSizes;
  final VoidCallback onClose;

  @override
  State<ExtensionPopup> createState() => _ExtensionPopupState();
}

class _ExtensionPopupState extends State<ExtensionPopup> {
  late final LadybirdController _controller;
  StreamSubscription<ExtensionContentSize>? _sizes;
  Timer? _giveUp;

  // The page lays itself out in the most room it can have, and the popup
  // shrinks to what it used. It stays hidden until then, or until it is clear
  // that the page is not going to say.
  Size _size = _maxPopupSize;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    _controller = LadybirdController();
    // Extensions' popups close themselves once they have done their job.
    _controller.onCloseRequested = () {
      if (mounted) widget.onClose();
    };
    _controller.navigate(widget.url);

    _sizes = widget.contentSizes.listen((size) {
      if (size.context.viewId != _controller.viewId || !mounted) return;
      setState(() {
        _measured = true;
        _size = Size(
          size.width.clamp(_minPopupSize.width, _maxPopupSize.width),
          size.height.clamp(_minPopupSize.height, _maxPopupSize.height),
        );
      });
    });
    _giveUp = Timer(const Duration(seconds: 3), () {
      if (mounted && !_measured) setState(() => _measured = true);
    });
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _sizes?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Nothing of the popup shows until it has its size: not its page, and not
    // the card it sits on, which would be as big as the most room it can have.
    return Offstage(
      offstage: !_measured,
      child: Material(
        elevation: 6,
        color: omniboxSurfaceColor(theme),
        borderRadius: BorderRadius.circular(kOmniboxFieldRadius),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: _size.width,
          height: _size.height,
          child: LadybirdView(controller: _controller),
        ),
      ),
    );
  }
}
