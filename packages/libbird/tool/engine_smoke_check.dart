// Engine smoke check: drives libengine's C ABI directly, with no Flutter and no
// window, to check that the parts of the embedding that break silently still
// work -- navigation, painting, and wheel input reaching the page.
//
// The ABI is positional, so an engine change that renumbers an event type (as
// Ladybird did when it inserted MouseCancel before MouseWheel) turns scrolling
// off without any compile error. Run this after moving the Ladybird pin:
//
//   flutter build macos --debug
//   APP=build/macos/Build/Products/Debug/flutterbird.app
//   mkdir -p /tmp/libbird-home && ln -sfn "$PWD/packages/libbird/third_party/ladybird/Base/res" /tmp/libbird-home/.lagom
//   (cd "$APP/Contents/MacOS" && HOME=/tmp/libbird-home dart run \
//       ../../../packages/libbird/tool/engine_smoke_check.dart \
//       "$APP/Contents/Resources/libengine.dylib")
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';

final coreVideo = ffi.DynamicLibrary.open(
    '/System/Library/Frameworks/CoreVideo.framework/CoreVideo');
final lockBase = coreVideo.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64),
    int Function(ffi.Pointer<ffi.Void>, int)>('CVPixelBufferLockBaseAddress');
final unlockBase = coreVideo.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64),
    int Function(ffi.Pointer<ffi.Void>, int)>('CVPixelBufferUnlockBaseAddress');
final baseAddress = coreVideo.lookupFunction<
    ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>),
    ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>)>(
    'CVPixelBufferGetBaseAddress');
final bytesPerRow = coreVideo.lookupFunction<
    ffi.Int64 Function(ffi.Pointer<ffi.Void>),
    int Function(ffi.Pointer<ffi.Void>)>('CVPixelBufferGetBytesPerRow');
final releasePixelBuffer = coreVideo.lookupFunction<
    ffi.Void Function(ffi.Pointer<ffi.Void>),
    void Function(ffi.Pointer<ffi.Void>)>('CVPixelBufferRelease');

late LadybirdBindings b;
late int view;
late int frameWidth;
late int frameHeight;

// Frames reach the embedder as CVPixelBuffers, so hash one through CoreVideo.
int? hashCurrentFrame() {
  final raw = b.get_latest_pixel_buffer(view);
  if (raw == ffi.nullptr) return null;

  final buffer = ffi.Pointer<ffi.Void>.fromAddress(raw.address);
  if (lockBase(buffer, 1) != 0) {
    releasePixelBuffer(buffer);
    return null;
  }

  final base = baseAddress(buffer);
  final stride = bytesPerRow(buffer);
  var hash = 1469598103934665603;
  for (var y = 0; y < frameHeight; y += 4) {
    for (var x = 0; x < frameWidth; x += 4) {
      final offset = y * stride + x * 4;
      for (var channel = 0; channel < 4; channel++) {
        hash ^= base[offset + channel];
        hash = (hash * 1099511628211) & 0xFFFFFFFFFFFFFFFF;
      }
    }
  }

  unlockBase(buffer, 1);
  releasePixelBuffer(buffer);
  return hash;
}

/// Ticks the engine until it has painted past [afterGeneration].
int? waitForFrameNewerThan(int afterGeneration, Duration timeout) {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 1));
    if (b.get_frame_generation(view) > afterGeneration) {
      frameWidth = b.get_iosurface_width(view);
      frameHeight = b.get_iosurface_height(view);
      final hash = hashCurrentFrame();
      if (hash != null) return hash;
    }
  }
  return null;
}

void main(List<String> args) {
  final lib = ffi.DynamicLibrary.open(args[0]);
  b = LadybirdBindings(lib);

  stdout.writeln('engine: ${args[0]}');
  b.init_ladybird();
  view = b.create_web_view();
  stdout.writeln('view id: $view');
  if (view < 0) exit(2);
  b.resize_window(view, 800, 600);

  // An element scroller under the pointer, plus tall document content behind it.
  const page = '<body style="margin:0;background:#fff">'
      '<div id="scroller" style="width:800px;height:600px;overflow:scroll">'
      '<div style="height:8000px;background:repeating-linear-gradient(#000 0 100px,#fff 100px 200px)"></div>'
      '</div>'
      '<div style="height:8000px"></div>'
      '</body>';
  final url = 'data:text/html;base64,${base64Encode(utf8.encode(page))}';
  final urlPtr = url.toNativeUtf8();
  b.navigate_to(view, urlPtr.cast());
  malloc.free(urlPtr);

  final painted = waitForFrameNewerThan(0, const Duration(seconds: 30));
  if (painted == null) {
    stdout.writeln('FAIL: nothing was painted');
    exit(3);
  }
  stdout.writeln('painted: ${frameWidth}x$frameHeight '
      'generation=${b.get_frame_generation(view)} hash=$painted');

  // A wheel event that arrives while the document is still becoming active is
  // dropped by the engine, so only start once the load has finished.
  final loadDeadline = DateTime.now().add(const Duration(seconds: 30));
  while (b.is_tab_loading(view) && DateTime.now().isBefore(loadDeadline)) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 2));
  }
  stdout.writeln('load finished: ${!b.is_tab_loading(view)}');

  // Page content keeps painting for a while after the load ends; wait for the
  // frames to stop before treating one as the pre-scroll baseline, or a later
  // paint of untouched content would pass for a scroll.
  int? settled;
  var lastGeneration = -1;
  var lastChange = DateTime.now();
  final settleDeadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(settleDeadline)) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 2));
    final generation = b.get_frame_generation(view);
    if (generation != lastGeneration) {
      lastGeneration = generation;
      lastChange = DateTime.now();
      settled = hashCurrentFrame() ?? settled;
      continue;
    }
    if (settled != null &&
        DateTime.now().difference(lastChange) > const Duration(seconds: 1)) {
      break;
    }
  }
  stdout.writeln('settled: generation=$lastGeneration hash=$settled');

  // Type 4 = LADYBIRD_MOUSE_WHEEL. A positive delta scrolls the page down (the
  // DOM convention the engine follows), so start by scrolling down: the page
  // starts at the top, where scrolling up would be clamped away and prove
  // nothing. Scrolling back the same amount must return the page to where it
  // was, which rules the change out as unrelated progressive painting.
  var wheeled = 0;

  /// Sends wheel deltas until the page paints something new, returning that
  /// frame's hash (null if it never painted).
  int? wheelUntilRepaint(double deltaY) {
    for (var attempt = 0; attempt < 5; attempt++) {
      final generationBefore = b.get_frame_generation(view);
      b.dispatch_mouse_event(view, 4, 400, 300, 0, 0, 0, 0.0, deltaY);
      wheeled += deltaY.toInt();
      final hash = waitForFrameNewerThan(
          generationBefore, const Duration(seconds: 3));
      if (hash != null) return hash;
    }
    return null;
  }

  final baseline = settled ?? painted;
  final afterWheel = wheelUntilRepaint(300);
  final wheelScrolled = afterWheel != null && afterWheel != baseline;
  stdout.writeln(afterWheel == null
      ? 'FAIL: wheel input painted nothing'
      : 'after wheel: hash=$afterWheel changed=${afterWheel != baseline}');

  final afterReverse = wheelUntilRepaint(-wheeled.toDouble());
  final reverseRestored = afterReverse == baseline;
  stdout.writeln(afterReverse == null
      ? 'FAIL: reverse wheel painted nothing'
      : 'after reverse wheel: hash=$afterReverse restored=$reverseRestored');

  // An event type the ABI does not define is rejected outright (the engine
  // says so on stderr); whether it *also* leaves the page untouched cannot be
  // asserted here, because a page keeps painting on its own (scrollbars fade).

  b.destroy_web_view(view);
  final passed = wheelScrolled && reverseRestored;
  stdout.writeln(passed
      ? 'OK: wheel input scrolls down and back to the same frame'
      : 'FAIL');
  exit(passed ? 0 : 1);
}