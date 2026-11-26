import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ladybird/ladybird.dart';

/// The width the button takes at the end of the address field.
const double kPictureInPictureButtonWidth = 38;

/// Floats the page's video. It is there while the page has a video that can
/// float, or has one floating.
class PictureInPictureButton extends StatefulWidget {
  const PictureInPictureButton({required this.tab, super.key});

  final LadybirdController tab;

  @override
  State<PictureInPictureButton> createState() => _PictureInPictureButtonState();
}

class _PictureInPictureButtonState extends State<PictureInPictureButton> {
  /// How often the page is asked. A video can appear, start or go at any time,
  /// long after the page has loaded.
  static const _interval = Duration(milliseconds: 1500);

  final LadybirdSiteBridge _bridge = LadybirdSiteBridge.instance;
  Timer? _poll;
  Timer? _afterPress;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(_interval, (_) => _refresh());
  }

  @override
  void didUpdateWidget(PictureInPictureButton old) {
    super.didUpdateWidget(old);
    if (old.tab.viewId != widget.tab.viewId) _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _afterPress?.cancel();
    super.dispose();
  }

  void _refresh() => _bridge.refreshVideoState(widget.tab.viewId);

  void _press() {
    _bridge.togglePictureInPicture(widget.tab.viewId);
    // Sooner than the next round, so the button answers the press.
    _afterPress?.cancel();
    _afterPress = Timer(const Duration(milliseconds: 400), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<VideoState>(
      valueListenable: _bridge.videoState(widget.tab.viewId),
      builder: (context, video, _) {
        if (!video.available) return const SizedBox.shrink();
        return IconButton(
          tooltip: video.active ? 'Bring the video back' : 'Picture in Picture',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: kPictureInPictureButtonWidth,
            height: 30,
          ),
          padding: EdgeInsets.zero,
          onPressed: _press,
          icon: Icon(
            Icons.picture_in_picture_alt,
            color: video.active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}
