import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ladybird/ladybird.dart';
import 'package:collection/collection.dart';

part 'browser.g.dart';

@Riverpod(keepAlive: true)
class BrowserTabController extends _$BrowserTabController {
  @override
  List<LadybirdController> build() {
    ref.onDispose(() {
      for (final controller in state) {
        controller.dispose();
      }
    });

    return [LadybirdController()];
  }

  LadybirdController add() {
    final controller = LadybirdController();
    final newState = state.toList();
    newState.add(controller);
    state = newState;

    return controller;
  }

  LadybirdController addExisting(int viewId) {
    final existing = state.firstWhereOrNull((e) => e.viewId == viewId);
    if (existing != null) return existing;

    final controller = LadybirdController.fromExistingViewId(viewId: viewId);
    final newState = state.toList();
    newState.add(controller);
    state = newState;

    return controller;
  }

  void remove(int viewId) {
    final newState = state.toList();
    final index = newState.indexWhere((e) => e.viewId == viewId);
    if (index < 0) return;

    final controller = newState.removeAt(index);
    controller.dispose();
    state = newState;
  }

  void reorder(int oldIndex, int newIndex) {
    final newState = state.toList();
    final item = newState.removeAt(oldIndex);
    newState.insert(newIndex, item);
    state = newState;
  }
}

@Riverpod(keepAlive: true)
LadybirdController? browserTab(Ref ref, int viewId) {
  final tabs = ref.watch(browserTabControllerProvider);
  return tabs.firstWhereOrNull((e) => e.viewId == viewId);
}
