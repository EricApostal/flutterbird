import 'dart:async';

import 'package:flutter/foundation.dart';

import 'session.dart';

/// The state behind one tool. It lives as long as the toolbox does, so that
/// what a panel shows survives the panel and the tab being switched away from.
abstract class ToolController extends ChangeNotifier {
  ToolController(this.session);

  final ToolboxSession session;
  bool _disposed = false;
  bool _notifyScheduled = false;

  bool get isDisposed => _disposed;

  /// The page has a new document, with actors of its own.
  void onTargetAvailable(DevToolsTarget target) {}

  /// The document the actors were for is gone.
  void onTargetDestroyed() {}

  /// The page is about to load another document.
  void onWillNavigate(String url) {}

  void onDocumentComplete() {}

  void onResources(String type, List<Map<String, Object?>> resources) {}

  void onResourceUpdates(String type, List<Map<String, Object?>> updates) {}

  /// Tells listeners once this turn of the event loop is over, so that a burst
  /// of events rebuilds a panel once.
  void changed() {
    if (_disposed || _notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
