import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bookmarks.g.dart';

/// A bookmark as the UI shows it: the page, its title, and the base64 PNG of
/// its favicon when the engine still has one.
class BirdBookmark {
  const BirdBookmark({required this.url, required this.title, this.favicon});

  final String url;
  final String title;
  final String? favicon;
}

/// The browser's bookmarks, owned by the UI.
///
/// Bookmarks are a feature of the browser's UI, not of the engine: nothing in
/// Ladybird reads them. The engine only lends the profile directory they live
/// in and the favicon PNGs they point at by hash, so the store lives here.
///
/// The file format is the one Ladybird's own frontend writes, so an existing
/// Bookmarks.json keeps working:
///
///     {"version": 2, "items": [{"type": "bookmark", ...}, {"type": "folder", ...}]}
class BookmarkStore {
  static const int _version = 2;
  static const String _fileName = 'Bookmarks.json';

  List<dynamic> _items = [];
  String? _filePath;
  bool _loaded = false;

  final Map<String, String?> _faviconCache = {};

  /// The bookmarks to show, flattening folders in document order.
  List<BirdBookmark> bookmarks({
    required String? directory,
    String? Function(String faviconHash)? faviconPng,
  }) {
    _ensureLoaded(directory);

    final bookmarks = <BirdBookmark>[];

    void collect(dynamic item) {
      if (item is! Map) return;

      if (item['type'] == 'bookmark') {
        final url = item['url'];
        if (url is! String || url.trim().isEmpty) return;

        final title = item['title'];
        bookmarks.add(
          BirdBookmark(
            url: url,
            title: (title is String && title.trim().isNotEmpty)
                ? title.trim()
                : url,
            favicon: faviconPng == null
                ? null
                : _faviconFor(faviconPng, item['faviconHash']),
          ),
        );
        return;
      }

      if (item['type'] == 'folder') {
        final children = item['children'];
        if (children is List) children.forEach(collect);
      }
    }

    _items.forEach(collect);
    return bookmarks;
  }

  /// Adds the current page as a bookmark, or removes it when it is already
  /// one.
  void toggle({
    required String? directory,
    required String url,
    required String title,
    String? faviconHash,
  }) {
    _ensureLoaded(directory);

    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) return;

    if (_removeByUrl(_items, normalizedUrl)) {
      _save();
      return;
    }

    final trimmedTitle = title.trim();
    final now = DateTime.now().millisecondsSinceEpoch;

    _items.add({
      'id': _generateId(),
      'type': 'bookmark',
      'dateAdded': now,
      'lastModified': now,
      'url': normalizedUrl,
      if (trimmedTitle.isNotEmpty) 'title': trimmedTitle,
      if (faviconHash != null) 'faviconHash': faviconHash,
    });
    _save();
  }

  void _ensureLoaded(String? directory) {
    // A call before the engine has a profile seeds a set in memory; load the
    // real profile's file as soon as there is a directory to read it from.
    if (_loaded && (_filePath != null || directory == null)) return;
    _loaded = true;

    if (directory == null) {
      _items = _defaultItems();
      return;
    }

    _filePath = '$directory/$_fileName';

    try {
      final file = File(_filePath!);
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map && decoded['items'] is List) {
          _items = List<dynamic>.from(decoded['items'] as List);
          return;
        }
      }
    } on FormatException catch (error) {
      debugPrint('Unable to parse bookmarks: $error');
    } on FileSystemException catch (error) {
      debugPrint('Unable to read bookmarks: $error');
    }

    _items = _defaultItems();
    _save();
  }

  String? _faviconFor(
    String? Function(String faviconHash) faviconPng,
    dynamic faviconHash,
  ) {
    if (faviconHash is! String || faviconHash.isEmpty) return null;
    if (_faviconCache.containsKey(faviconHash)) {
      return _faviconCache[faviconHash];
    }

    final encoded = faviconPng(faviconHash);
    _faviconCache[faviconHash] = encoded;
    return encoded;
  }

  bool _removeByUrl(List<dynamic> items, String url) {
    for (var i = 0; i < items.length; ++i) {
      final item = items[i];
      if (item is! Map) continue;

      if (item['type'] == 'bookmark' && item['url'] == url) {
        items.removeAt(i);
        return true;
      }

      if (item['type'] == 'folder') {
        final children = item['children'];
        if (children is List && _removeByUrl(children, url)) return true;
      }
    }

    return false;
  }

  void _save() {
    final path = _filePath;
    if (path == null) return;

    try {
      final file = File(path);
      file.parent.createSync(recursive: true);

      final temporary = File('$path.tmp');
      temporary.writeAsStringSync(
        jsonEncode({'version': _version, 'items': _items}),
        flush: true,
      );
      temporary.renameSync(path);
    } on FileSystemException catch (error) {
      debugPrint('Unable to write bookmarks: $error');
    }
  }

  // What a fresh profile starts with, matching what Ladybird's store seeded.
  List<dynamic> _defaultItems() {
    final now = DateTime.now().millisecondsSinceEpoch;

    Map<String, dynamic> bookmark(String url, String title) => {
      'id': _generateId(),
      'type': 'bookmark',
      'dateAdded': now,
      'lastModified': now,
      'url': url,
      'title': title,
    };

    return [
      bookmark('https://ladybird.org/', 'Ladybird'),
      bookmark(
        'https://github.com/LadybirdBrowser/ladybird',
        'Ladybird GitHub',
      ),
      bookmark('https://discord.com/invite/nvfjVJ4Svh', 'Ladybird Discord'),
    ];
  }

  static String _generateId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // RFC 4122 version 4.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    return '${hex.take(4).join()}-${hex.skip(4).take(2).join()}-'
        '${hex.skip(6).take(2).join()}-${hex.skip(8).take(2).join()}-'
        '${hex.skip(10).take(6).join()}';
  }
}

@Riverpod(keepAlive: true)
BookmarkStore bookmarkStore(Ref ref) => BookmarkStore();
