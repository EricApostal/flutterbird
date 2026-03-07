import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ladybird/ladybird.dart';

part 'browser.g.dart';

@Riverpod(keepAlive: true)
class BrowserTabController extends _$BrowserTabController {
  @override
  List<LadybirdController> build() {
    return [LadybirdController()];
  }

  LadybirdController add() {
    final controller = LadybirdController();
    final newState = state.toList();
    newState.add(controller);
    state = newState;

    return controller;
  }

  void remove(int viewId) {
    final newState = state.toList();
    newState.removeWhere((e) => e.viewId == viewId);
    state = newState;
  }
}
