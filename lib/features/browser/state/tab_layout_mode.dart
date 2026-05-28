import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tab_layout_mode.g.dart';

enum BrowserTabLayoutMode { horizontal, vertical }

@Riverpod(keepAlive: true)
class BrowserTabLayoutModeController extends _$BrowserTabLayoutModeController {
  @override
  BrowserTabLayoutMode build() {
    return BrowserTabLayoutMode.horizontal;
  }

  void toggle() {
    state = state == BrowserTabLayoutMode.horizontal
        ? BrowserTabLayoutMode.vertical
        : BrowserTabLayoutMode.horizontal;
  }

  void setHorizontal() {
    state = BrowserTabLayoutMode.horizontal;
  }

  void setVertical() {
    state = BrowserTabLayoutMode.vertical;
  }
}
