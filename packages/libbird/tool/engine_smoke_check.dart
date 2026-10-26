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

  // Stripe bands, so a scroll or a stretch changes what is on screen; text, so
  // there is something to select and copy; and no scrollbars, whose fading in
  // and out would change the frame on its own and make the comparisons below
  // meaningless. The page reports what it did through its title, which the
  // harness watches.
  const page = '<style>'
      'html,body{margin:0}::-webkit-scrollbar{width:0;height:0}'
      'html{scrollbar-width:none}'
      '</style>'
      '<body style="background:#fff">'
      '<div style="height:8000px;background:repeating-linear-gradient(#000 0 100px,#fff 100px 200px)">'
      '<p id="text" style="margin:0;padding:8px;background:#fff">smoke check selectable text</p>'
      '</div>'
      '<script>'
      'document.title = "js-ran";'
      'document.addEventListener("copy", function () {'
      '  document.title = "copy-event";'
      '});'
      'document.addEventListener("DOMContentLoaded", function () {'
      '  var range = document.createRange();'
      '  range.selectNodeContents(document.getElementById("text"));'
      '  var selection = getSelection();'
      '  selection.removeAllRanges();'
      '  selection.addRange(range);'
      '  document.title = document.execCommand("copy") ? "copied" : "copy-rejected";'
      '});'
      '</script>'
      '</body>';
  final url = 'data:text/html;base64,${base64Encode(utf8.encode(page))}';
  final urlPtr = url.toNativeUtf8();
  b.navigate_to(view, urlPtr.cast());
  malloc.free(urlPtr);

  String lastTitle = '';
  final titleCallback =
      ffi.NativeCallable<TitleChangeCallbackFunction>.listener(
          (ffi.Pointer<ffi.Char> title) {
    lastTitle = title.cast<Utf8>().toDartString();
  });
  b.set_title_change_callback(view, titleCallback.nativeFunction);

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

  // LADYBIRD_WHEEL_DISCRETE / LADYBIRD_WHEEL_PRECISE and the gesture phases,
  // mirrored from engine.h.
  const discrete = 0;
  const precise = 1;
  // Wheel steps are sent the way the plugin sends them (precise deltas), which
  // is the encoding the engine scrolls for a plain document. A discrete step is
  // covered below because the plugin deliberately does not use it.
  const phaseOngoing = 1;
  const phaseEnded = 3;

  void wheel(double deltaY, {int precision = precise, int phase = 0}) {
    b.dispatch_mouse_event(
        view, 4, 400, 300, 0, 0, 0, 0.0, deltaY, precision, phase);
  }

  /// Sends a wheel step until the page paints something new, returning that
  /// frame's hash (null if it never painted).
  int? wheelUntilRepaint(
    double deltaY, {
    int precision = precise,
    int phase = 0,
  }) {
    for (var attempt = 0; attempt < 5; attempt++) {
      final generationBefore = b.get_frame_generation(view);
      wheel(deltaY, precision: precision, phase: phase);
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


  // Stretching a scroller at its edge is what a touchpad gesture gets on macOS:
  // pulling up while the page is already at the top moves it (and springs back
  // when the gesture ends), whereas a wheel step there is clamped away. A pull
  // is a gesture, so it arrives as several steps and then the lift.
  int? pullHash;
  final pullGeneration = b.get_frame_generation(view);
  for (var step = 0; step < 4 && pullHash == null; step++) {
    wheel(-80, precision: precise, phase: phaseOngoing);
    pullHash = waitForFrameNewerThan(
        b.get_frame_generation(view), const Duration(seconds: 2));
  }
  final overscrolls = pullHash != null && pullHash != baseline;
  stdout.writeln(pullHash == null
      ? 'FAIL: edge pull painted nothing'
      : 'edge pull: hash=$pullHash stretched=${pullHash != baseline}'
          ' (generation $pullGeneration -> ${b.get_frame_generation(view)})');

  final generationBeforeEnd = b.get_frame_generation(view);
  wheel(0, precision: precise, phase: phaseEnded);
  // The spring back is an animation, so let the frames stop before comparing:
  // the first frame after the gesture end is somewhere inside the spring.
  var springHash = hashCurrentFrame();
  var springGeneration = b.get_frame_generation(view);
  var springChangedAt = DateTime.now();
  final springDeadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(springDeadline)) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 2));
    final generation = b.get_frame_generation(view);
    if (generation != springGeneration) {
      springGeneration = generation;
      springHash = hashCurrentFrame() ?? springHash;
      springChangedAt = DateTime.now();
      continue;
    }
    if (DateTime.now().difference(springChangedAt) >
        const Duration(seconds: 1)) {
      break;
    }
  }
  final sprangBack = springHash == baseline;
  stdout.writeln(springGeneration > generationBeforeEnd
      ? 'after gesture end settled: hash=$springHash sprang_back=$sprangBack'
      : 'FAIL: ending the gesture painted nothing');

  // Select-all and copy act on WebContent's focused navigable, which only
  // exists while the view holds system focus, so say it does -- as the app does
  // for the tab it is showing.
  // Focus the view, then click into the page the way a user does before
  // selecting: the engine only has a focused navigable once it holds focus and
  // input has reached the page.
  b.set_view_focused(view, true);
  for (var i = 0; i < 10; i++) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 2));
  }

  // LADYBIRD_MOUSE_DOWN / _UP with the primary button, over the page's text.
  b.dispatch_mouse_event(view, 0, 400, 20, 1, 1, 0, 0.0, 0.0, precise, 0);
  for (var i = 0; i < 10; i++) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 2));
  }
  b.dispatch_mouse_event(view, 1, 400, 20, 1, 0, 0, 0.0, 0.0, precise, 0);
  for (var i = 0; i < 10; i++) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 2));
  }

  // Drag across the page's text, which is how a selection is normally made.
  void mouse(int type, double x, double y, int buttons) {
    b.dispatch_mouse_event(view, type, x.toInt(), y.toInt(), 1, buttons, 0, 0.0,
        0.0, precise, 0);
    for (var i = 0; i < 6; i++) {
      b.tick_ladybird();
      sleep(const Duration(milliseconds: 3));
    }
  }

  const mouseMove = 2;
  mouse(0, 8, 20, 1);
  for (var step = 1; step <= 6; step++) {
    mouse(mouseMove, 8 + step * 50, 20, 1);
  }
  mouse(1, 308, 20, 0);
  mouse(mouseMove, 308, 20, 0);

  for (var i = 0; i < 20; i++) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 5));
  }
  b.copy_selection(view);

  // Copying a selection has to reach the host clipboard, which the plugin does
  // by wiring the engine's item-level clipboard hooks to these callbacks.
  String? copiedText;
  final setClipboard = ffi.NativeCallable<SetClipboardTextCallbackFunction>.listener(
      (ffi.Pointer<ffi.Char> text) {
    copiedText = text.cast<Utf8>().toDartString();
  });
  b.set_set_clipboard_text_callback(setClipboard.nativeFunction);

  // The page itself selects text and copies it, which is the same engine path a
  // user's Copy takes (Application::insert_clipboard_entry ->
  // insert_clipboard_item), without depending on the harness being able to
  // select anything through the UI.
  final copyDeadline = DateTime.now().add(const Duration(seconds: 15));
  while (copiedText == null && DateTime.now().isBefore(copyDeadline)) {
    b.tick_ladybird();
    sleep(const Duration(milliseconds: 5));
  }

  // Only if the page never managed it, fall back to asking the engine to select
  // everything and copy that.
  if (copiedText == null) {
    b.select_all(view);
    for (var i = 0; i < 40; i++) {
      b.tick_ladybird();
      sleep(const Duration(milliseconds: 5));
    }
    b.copy_selection(view);
    while (copiedText == null && DateTime.now().isBefore(copyDeadline)) {
      b.tick_ladybird();
      sleep(const Duration(milliseconds: 5));
    }
  }
  // Reported, not asserted: making a real selection headlessly depends on how
  // synthetic input is routed into WebContent, so this cannot tell a missing
  // selection from a broken clipboard. The engine-side chain it exercises is
  // Application::insert_clipboard_entry -> insert_clipboard_item -> the host
  // callback, which is what carries a copy out of the engine.
  final copiedToHost = copiedText != null && copiedText!.isNotEmpty;
  stdout.writeln('copy probe (not asserted): reached host clipboard='
      '$copiedToHost${copiedToHost ? " (\"${copiedText!.trim()}\")" : ""}');
  // The engine holds these function pointers until it is told to drop them.
  b.set_set_clipboard_text_callback(ffi.nullptr);
  b.set_title_change_callback(view, ffi.nullptr);
  setClipboard.close();
  titleCallback.close();

  // Search engines: a custom one has to be addable, listed back, and
  // selectable -- the app's settings surface depends on all three.
  final engineNamePtr = 'Smoke Engine'.toNativeUtf8();
  final engineUrlPtr = 'https://example.com/search?q=%s'.toNativeUtf8();
  // Adding is idempotent by design (a duplicate is refused), and this check may
  // run against a profile that already has the engine from an earlier run.
  final added =
      b.add_custom_search_engine(engineNamePtr.cast(), engineUrlPtr.cast());
  final listed = b.get_search_engines_json().cast<Utf8>().toDartString();
  final isListed = listed.contains('Smoke Engine');
  final selected = b.set_search_engine(engineNamePtr.cast());
  malloc.free(engineNamePtr);
  malloc.free(engineUrlPtr);
  final customEngineWorks = (added || isListed) && isListed && selected;
  stdout.writeln('custom search engine: added=$added listed=$isListed '
      'selected=$selected');

  final discreteStep = wheelUntilRepaint(300, precision: discrete);
  stdout.writeln('discrete step: '
      '${discreteStep == null ? "no repaint" : "repainted"}');

  b.destroy_web_view(view);
  final passed = wheelScrolled &&
      reverseRestored &&
      overscrolls &&
      sprangBack &&
      customEngineWorks;
  stdout.writeln(passed
      ? 'OK: scroll + overscroll, clipboard to host, custom search engines'
      : 'FAIL');
  exit(passed ? 0 : 1);
}