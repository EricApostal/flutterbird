import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';

// Small snapshots of each tab's page, shown by the hover preview on the tab
// strip and the vertical tab sidebar.
//
// Only the selected tab has a mounted view (every tab is its own route, and an
// unmounted tab has no texture to read), so a tab's preview is the last frame
// it showed while it was on screen -- captured by TabPreviewCapturer -- not a
// live one. Snapshots are taken straight at thumbnail size, so holding one per
// tab stays cheap.
class TabPreviewCache {
  TabPreviewCache._();
  static final TabPreviewCache instance = TabPreviewCache._();

  // The width, in physical pixels, a snapshot is taken at. The popup shows it
  // at 320 logical pixels, so this covers a 2x display without a resample.
  static const double snapshotWidth = 640;

  static const int _maxEntries = 32;

  // Insertion order == LRU order.
  final LinkedHashMap<int, ValueNotifier<ui.Image?>> _entries =
      LinkedHashMap<int, ValueNotifier<ui.Image?>>();
  final Set<int> _inFlight = <int>{};

  // The tab's current snapshot, which changes when a newer one is captured.
  ValueListenable<ui.Image?> listenableFor(int viewId) => _notifierFor(viewId);

  ValueNotifier<ui.Image?> _notifierFor(int viewId) {
    var notifier = _entries.remove(viewId);
    notifier ??= ValueNotifier<ui.Image?>(null);
    _entries[viewId] = notifier;

    while (_entries.length > _maxEntries) {
      final oldest = _entries.keys.first;
      _release(_entries.remove(oldest)!);
    }
    return notifier;
  }

  // Captures [viewId]'s page if its view is on screen, replacing the previous
  // snapshot. One capture per tab at a time.
  Future<void> capture(int viewId) async {
    if (!_inFlight.add(viewId)) return;
    try {
      final image = await BrowserWindow.captureSnapshotFor(
        viewId,
        maxWidth: snapshotWidth,
      );
      if (image == null) return;

      final notifier = _notifierFor(viewId);
      final previous = notifier.value;
      notifier.value = image;
      _disposeLater(previous);
    } finally {
      _inFlight.remove(viewId);
    }
  }

  // Called when a tab closes.
  void evict(int viewId) {
    final notifier = _entries.remove(viewId);
    if (notifier != null) _release(notifier);
  }

  void _release(ValueNotifier<ui.Image?> notifier) {
    final image = notifier.value;
    notifier.value = null;
    _disposeLater(image);
  }

  // A popup may still be painting the image it was handed, so a replaced image
  // is only disposed once that frame is long gone.
  void _disposeLater(ui.Image? image) {
    if (image == null) return;
    Timer(const Duration(seconds: 2), image.dispose);
  }
}
