import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ladybird/ladybird.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Resolves and caches the directory downloads are saved to, then wires the
// engine's download-path/error callbacks. Must be awaited before the first
// LadybirdController is constructed (main() does this before runApp), since
// the native callback is synchronous and can't await path_provider itself.
Future<void> initializeDownloads() async {
  final downloadsDir = await _resolveDownloadsDirectory();

  LadybirdController.onAskUserForDownloadPath = (suggestion) {
    return _uniqueDownloadPath(downloadsDir, suggestion);
  };
  LadybirdController.onDisplayErrorDialog = (message) {
    debugPrint('Download error: $message');
  };
}

Future<String> _resolveDownloadsDirectory() async {
  // getDownloadsDirectory() only has a real answer on desktop platforms;
  // Android has no shared "Downloads" folder concept, so fall back to the
  // app's own documents directory there.
  try {
    final dir = await getDownloadsDirectory();
    if (dir != null) return dir.path;
  } catch (_) {
    // Unsupported on this platform.
  }
  return (await getApplicationDocumentsDirectory()).path;
}

// The engine hands us a suggested file name and expects a final destination
// path back synchronously; it does not dedupe that path against the
// filesystem itself, so do it here (mirrors path_for_downloaded_file's
// headless-mode "(n)" suffixing in Application.cpp).
String _uniqueDownloadPath(String directory, String fileName) {
  var candidate = p.join(directory, fileName);
  if (!File(candidate).existsSync()) return candidate;

  final extension = p.extension(fileName);
  final title = p.basenameWithoutExtension(fileName);
  for (var index = 1; ; index++) {
    candidate = p.join(directory, '$title ($index)$extension');
    if (!File(candidate).existsSync()) return candidate;
  }
}
