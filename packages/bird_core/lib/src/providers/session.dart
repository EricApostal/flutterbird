import 'package:bird_session/bird_session.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';

import 'browser.dart';

/// Which tabs are in which window.
///
/// [browserTabControllerProvider] holds every tab's controller, whichever
/// window it is in, and this says where each one is and in what order. Change
/// it through the app's browser shell, which keeps the two in step.
///
/// It starts as one window holding the tabs that exist, which starts the
/// engine if nothing has yet.
class BrowserSessionNotifier extends Notifier<BrowserSession> {
  @override
  BrowserSession build() => BrowserSession.single([
    for (final controller in ref.read(browserTabControllerProvider))
      controller.viewId,
  ]);

  BrowserSession get current => state;

  void commit(BrowserSession next) {
    if (identical(next, state)) return;
    state = next;
  }
}

final browserSessionProvider =
    NotifierProvider<BrowserSessionNotifier, BrowserSession>(
      BrowserSessionNotifier.new,
    );

/// One window, or null once it has closed.
final browserWindowProvider = Provider.family<BrowserWindowModel?, int>(
  (ref, windowId) => ref.watch(
    browserSessionProvider.select((session) => session.window(windowId)),
  ),
);

/// The tabs of one window, in the order its strip shows them.
final windowTabsProvider = Provider.family<List<LadybirdController>, int>((
  ref,
  windowId,
) {
  final window = ref.watch(browserWindowProvider(windowId));
  final controllers = ref.watch(browserTabControllerProvider);
  return [
    for (final tabId in window?.tabIds ?? const <int>[])
      ?controllers.firstWhereOrNull((c) => c.viewId == tabId),
  ];
});
