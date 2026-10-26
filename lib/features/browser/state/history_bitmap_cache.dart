import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

// Rendering cache for the swipe-back page stack, keyed by each tab's viewId
// and each session history entry's stable `step` (from
// LadybirdController.sessionHistoryNotifier -- Ladybird's own history
// mirror). This never decides *what* history looks like, only caches
// snapshots of pages that mirror already says exist.
class HistoryBitmapCache {
  HistoryBitmapCache._();
  static final HistoryBitmapCache instance = HistoryBitmapCache._();

  static const int _maxMemoryEntries = 8;

  // The frames a tab has presented, one per view, newest last -- the most
  // recent of the per-step snapshots below, which is what a view being shown
  // again stands on until its own texture has something to paint. Memory only,
  // and per session on purpose: view ids are reused by a fresh engine, so a
  // frame from an earlier run must never be shown over a new view. Clones
  // share pixel data with the per-step entries, so this costs one frame per
  // tab at most -- the same order as the entries it sits next to.
  static const int _maxLastFrames = 8;
  final LinkedHashMap<int, ui.Image> _lastFrameByView =
      LinkedHashMap<int, ui.Image>();

  // Insertion order == LRU order; re-inserting a key on access moves it to
  // the most-recently-used (last) position.
  final LinkedHashMap<_CacheKey, ui.Image> _memory =
      LinkedHashMap<_CacheKey, ui.Image>();

  Future<Directory> _tabDirectory(int viewId) async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}/history_snapshots/$viewId');
  }

  Future<File> _entryFile(int viewId, int step) async {
    final dir = await _tabDirectory(viewId);
    return File('${dir.path}/$step.png');
  }

  Future<void> store(int viewId, int step, ui.Image image) async {
    final key = _CacheKey(viewId, step);
    _rememberInMemory(key, image);
    _rememberLastFrame(viewId, image);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final file = await _entryFile(viewId, step);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
  }

  // The last frame `viewId` presented, if it has been captured this session.
  // Returns a handle the caller owns (the cache may drop its own copy at any
  // point), so it stays valid for as long as the caller holds it.
  ui.Image? cloneLastFrame(int viewId) => _lastFrameByView[viewId]?.clone();

  void _rememberLastFrame(int viewId, ui.Image image) {
    _lastFrameByView.remove(viewId)?.dispose();
    // A clone, not the image itself: the per-step entry that owns `image`
    // disposes it when it is evicted, which must not invalidate this frame.
    _lastFrameByView[viewId] = image.clone();
    while (_lastFrameByView.length > _maxLastFrames) {
      _lastFrameByView.remove(_lastFrameByView.keys.first)?.dispose();
    }
  }

  // Returns the cached snapshot for (viewId, step), if any -- from memory if
  // still resident, otherwise lazily decoded from disk. Null means no
  // snapshot has ever been captured for this entry (caller should fall back
  // to a placeholder).
  Future<ui.Image?> load(int viewId, int step) async {
    final key = _CacheKey(viewId, step);
    final cached = _memory.remove(key);
    if (cached != null) {
      _memory[key] = cached;
      return cached;
    }

    final file = await _entryFile(viewId, step);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _rememberInMemory(key, frame.image);
    return frame.image;
  }

  void _rememberInMemory(_CacheKey key, ui.Image image) {
    _memory.remove(key)?.dispose();
    _memory[key] = image;
    while (_memory.length > _maxMemoryEntries) {
      _memory.remove(_memory.keys.first)?.dispose();
    }
  }

  // Called when `step` disappears from a tab's sessionHistoryNotifier
  // between two emissions -- Ladybird itself truncated or replaced that
  // entry, so its snapshot is no longer reachable.
  Future<void> evictEntry(int viewId, int step) async {
    _memory.remove(_CacheKey(viewId, step))?.dispose();

    final file = await _entryFile(viewId, step);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> evictTab(int viewId) async {
    _lastFrameByView.remove(viewId)?.dispose();

    final staleKeys = _memory.keys
        .where((key) => key.viewId == viewId)
        .toList(growable: false);
    for (final key in staleKeys) {
      _memory.remove(key)?.dispose();
    }

    final dir = await _tabDirectory(viewId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

class _CacheKey {
  const _CacheKey(this.viewId, this.step);

  final int viewId;
  final int step;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey && other.viewId == viewId && other.step == step;

  @override
  int get hashCode => Object.hash(viewId, step);
}
