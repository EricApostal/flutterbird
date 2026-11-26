import 'package:flutter/foundation.dart';
import 'package:ladybird/ladybird.dart';

class _TabSearch {
  bool isOpen = false;
  String query = '';

  /// Counts the asks for the keyboard, so that asking again while the bar is
  /// open brings it back to the bar.
  int focusRequests = 0;
}

/// Which tabs have their find bar open, and what each is looking for. As in
/// Chrome, a search belongs to its tab, and the words are kept for next time.
class FindInPage extends ChangeNotifier {
  FindInPage._();

  static final FindInPage instance = FindInPage._();

  final Map<int, _TabSearch> _tabs = {};

  _TabSearch _tab(int viewId) => _tabs.putIfAbsent(viewId, _TabSearch.new);

  bool isOpen(int viewId) => _tabs[viewId]?.isOpen ?? false;

  String queryOf(int viewId) => _tabs[viewId]?.query ?? '';

  int focusRequestsOf(int viewId) => _tabs[viewId]?.focusRequests ?? 0;

  /// Opens the bar, or gives it the keyboard if it is open.
  void open(int viewId) {
    final tab = _tab(viewId);
    final wasOpen = tab.isOpen;
    tab
      ..isOpen = true
      ..focusRequests += 1;
    if (!wasOpen && tab.query.isNotEmpty) {
      LadybirdFind.instance.find(viewId, tab.query);
    }
    notifyListeners();
  }

  void search(int viewId, String query) {
    _tab(viewId).query = query;
    LadybirdFind.instance.find(viewId, query);
    notifyListeners();
  }

  /// Goes to the next or previous match, opening the bar first if need be.
  void step(int viewId, {required bool forwards}) {
    if (!isOpen(viewId)) {
      open(viewId);
      return;
    }
    if (queryOf(viewId).isEmpty) return;
    forwards
        ? LadybirdFind.instance.next(viewId)
        : LadybirdFind.instance.previous(viewId);
  }

  void close(int viewId) {
    final tab = _tabs[viewId];
    if (tab == null || !tab.isOpen) return;
    tab.isOpen = false;
    LadybirdFind.instance.end(viewId);
    notifyListeners();
  }
}
