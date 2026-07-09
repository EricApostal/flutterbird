import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/state/history_bitmap_cache.dart';
import 'package:ladybird/ladybird.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tab_history.g.dart';

// Best-effort metadata for a session history entry that Ladybird's mirror
// doesn't carry (LadybirdSessionHistoryEntry has no title/favicon field) --
// captured live from titleNotifier/faviconNotifier whenever that step is
// current. Purely cosmetic for the swipe-back placeholder; never used to
// decide what the history stack contains.
class TabHistoryEntryMeta {
  const TabHistoryEntryMeta({this.title, this.favicon});

  final String? title;
  final dynamic favicon;
}

class TabHistoryState {
  const TabHistoryState({
    required this.entries,
    required this.optimisticCurrentStep,
    required this.meta,
  });

  // Ladybird's own session history mirror, unmodified -- the real
  // back/forward stack, in order.
  final List<LadybirdSessionHistoryEntry> entries;

  // Set only to bridge the gap between a gesture-driven pop that Flutter has
  // already animated to completion and Ladybird's async confirmation of the
  // resulting goBack(). Cleared as soon as `entries` itself reports that
  // step as current. Never used to invent stack contents.
  final int? optimisticCurrentStep;

  final Map<int, TabHistoryEntryMeta> meta;

  int? get _engineCurrentStep {
    for (final entry in entries) {
      if (entry.current) return entry.step;
    }
    return null;
  }

  // The step the UI should currently treat as "on screen".
  int? get effectiveCurrentStep {
    final optimistic = optimisticCurrentStep;
    if (optimistic != null && entries.any((e) => e.step == optimistic)) {
      return optimistic;
    }
    return _engineCurrentStep;
  }

  bool canPopFrom(int step) {
    final index = entries.indexWhere((e) => e.step == step);
    return index > 0;
  }
}

// Per-tab mirror of Ladybird's session history, plus the bitmap-capture
// bookkeeping the swipe-back UI needs. Never reconstructs history -- entries
// always come straight from LadybirdController.sessionHistoryNotifier.
@Riverpod(keepAlive: true)
class TabHistoryController extends _$TabHistoryController {
  static const _captureSettleDelay = Duration(milliseconds: 500);

  LadybirdController? _controller;
  int? _lastKnownCurrentStep;
  Timer? _captureDebounce;
  bool _wasLoading = false;

  @override
  TabHistoryState build(int viewId) {
    final controller = ref.watch(browserTabProvider(viewId));
    _controller = controller;
    if (controller == null) {
      return const TabHistoryState(
        entries: [],
        optimisticCurrentStep: null,
        meta: {},
      );
    }

    void onHistoryChanged() => _onSessionHistoryChanged(controller);
    void onLoadingChanged() => _onLoadingChanged(controller);
    void onTitleChanged() => _onTitleChanged(controller);
    void onFaviconChanged() => _onFaviconChanged(controller);

    controller.sessionHistoryNotifier.addListener(onHistoryChanged);
    controller.isLoadingNotifier.addListener(onLoadingChanged);
    controller.titleNotifier.addListener(onTitleChanged);
    controller.faviconNotifier.addListener(onFaviconChanged);

    ref.onDispose(() {
      controller.sessionHistoryNotifier.removeListener(onHistoryChanged);
      controller.isLoadingNotifier.removeListener(onLoadingChanged);
      controller.titleNotifier.removeListener(onTitleChanged);
      controller.faviconNotifier.removeListener(onFaviconChanged);
      _captureDebounce?.cancel();
    });

    final entries = _sorted(controller.sessionHistoryNotifier.value);
    _lastKnownCurrentStep = _currentStepOf(entries);
    return TabHistoryState(
      entries: entries,
      optimisticCurrentStep: null,
      meta: const {},
    );
  }

  int? _currentStepOf(List<LadybirdSessionHistoryEntry> entries) {
    for (final entry in entries) {
      if (entry.current) return entry.step;
    }
    return null;
  }

  // Ladybird's mirror should already be in step order, but state.entries is
  // used positionally (canPopFrom, goBack's "step before current") -- sort
  // defensively once here so every consumer agrees on the same order.
  List<LadybirdSessionHistoryEntry> _sorted(
    List<LadybirdSessionHistoryEntry> entries,
  ) {
    final sorted = [...entries];
    sorted.sort((a, b) => a.step.compareTo(b.step));
    return sorted;
  }

  void _onSessionHistoryChanged(LadybirdController controller) {
    final newEntries = _sorted(controller.sessionHistoryNotifier.value);
    final oldSteps = state.entries.map((e) => e.step).toSet();
    final newSteps = newEntries.map((e) => e.step).toSet();

    for (final step in oldSteps.difference(newSteps)) {
      HistoryBitmapCache.instance.evictEntry(viewId, step);
    }

    final newCurrentStep = _currentStepOf(newEntries);
    final previousCurrentStep = _lastKnownCurrentStep;
    if (previousCurrentStep != null &&
        newCurrentStep != previousCurrentStep &&
        oldSteps.contains(previousCurrentStep)) {
      // Best-effort "final" snapshot of the step we're leaving -- covers
      // pushState, which has no loading-state transition to hook.
      unawaited(_captureFor(previousCurrentStep));
    }
    _lastKnownCurrentStep = newCurrentStep;

    var optimistic = state.optimisticCurrentStep;
    if (optimistic != null && newCurrentStep == optimistic) {
      optimistic = null;
    }

    final newMeta = Map<int, TabHistoryEntryMeta>.from(state.meta)
      ..removeWhere((step, _) => !newSteps.contains(step));

    state = TabHistoryState(
      entries: newEntries,
      optimisticCurrentStep: optimistic,
      meta: newMeta,
    );
  }

  void _onLoadingChanged(LadybirdController controller) {
    if (controller.isLoadingNotifier.value) {
      _wasLoading = true;
      _captureDebounce?.cancel();
      return;
    }
    if (!_wasLoading) return;
    _wasLoading = false;

    _captureDebounce?.cancel();
    _captureDebounce = Timer(_captureSettleDelay, () {
      final step = _currentStepOf(controller.sessionHistoryNotifier.value);
      if (step != null) unawaited(_captureFor(step));
    });
  }

  void _onTitleChanged(LadybirdController controller) {
    final step = _currentStepOf(controller.sessionHistoryNotifier.value);
    if (step != null) _updateMeta(step, title: controller.titleNotifier.value);
  }

  void _onFaviconChanged(LadybirdController controller) {
    final step = _currentStepOf(controller.sessionHistoryNotifier.value);
    if (step != null) {
      _updateMeta(step, favicon: controller.faviconNotifier.value);
    }
  }

  void _updateMeta(int step, {String? title, dynamic favicon}) {
    final existing = state.meta[step];
    final updated = TabHistoryEntryMeta(
      title: title ?? existing?.title,
      favicon: favicon ?? existing?.favicon,
    );
    state = TabHistoryState(
      entries: state.entries,
      optimisticCurrentStep: state.optimisticCurrentStep,
      meta: {...state.meta, step: updated},
    );
  }

  Future<void> _captureFor(int step) async {
    final image = await BrowserWindow.captureSnapshotFor(viewId);
    if (image == null) return;
    await HistoryBitmapCache.instance.store(viewId, step, image);
  }

  // Safety-net capture for when the tab is backgrounded/switched away, in
  // case the debounce in _onLoadingChanged never got a chance to fire.
  void captureCurrentNow() {
    final controller = _controller;
    if (controller == null) return;
    final step = _currentStepOf(controller.sessionHistoryNotifier.value);
    if (step != null) unawaited(_captureFor(step));
  }

  // Called by the nested Navigator's onDidRemovePage once a swipe/predictive
  // back gesture has already animated to completion on Flutter's side.
  // Ladybird remains the only authority on whether/where this actually
  // navigates; this only bridges the gap until sessionHistoryNotifier
  // confirms it, so the revealed page keeps showing its own correct bitmap
  // instead of flashing something else in between.
  void goBack() {
    final controller = _controller;
    if (controller == null) return;

    final steps = state.entries.map((e) => e.step).toList(growable: false);
    final currentStep = state.effectiveCurrentStep;
    final currentIndex = currentStep == null ? -1 : steps.indexOf(currentStep);
    if (currentIndex <= 0) return;

    final targetStep = steps[currentIndex - 1];
    state = TabHistoryState(
      entries: state.entries,
      optimisticCurrentStep: targetStep,
      meta: state.meta,
    );
    controller.goBack();
  }
}
