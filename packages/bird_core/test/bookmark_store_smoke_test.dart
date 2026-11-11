import 'dart:convert';
import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bookmarks load, toggle and persist', () {
    final dir = Directory.systemTemp.createTempSync('bookmarks_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    File('${dir.path}/Bookmarks.json').writeAsStringSync(
      jsonEncode({
        'version': 2,
        'items': [
          {
            'id': 'f1',
            'type': 'folder',
            'title': 'Work',
            'children': [
              {
                'id': 'b1',
                'type': 'bookmark',
                'url': 'https://example.com/',
                'title': 'Example',
                'faviconHash': 'h1',
              },
            ],
          },
          {'id': 'b2', 'type': 'bookmark', 'url': 'https://second.example/'},
        ],
      }),
    );

    final store = BookmarkStore();
    final bookmarks = store.bookmarks(
      directory: dir.path,
      faviconPng: (hash) => hash == 'h1' ? 'YmFzZTY0' : null,
    );

    expect(bookmarks.map((bookmark) => bookmark.url).toList(), [
      'https://example.com/',
      'https://second.example/',
    ]);
    expect(bookmarks.first.title, 'Example');
    expect(bookmarks.first.favicon, 'YmFzZTY0');
    expect(bookmarks.last.title, 'https://second.example/');

    store.toggle(
      directory: dir.path,
      url: 'https://third.example/',
      title: 'Third',
      faviconHash: 'h2',
    );
    expect(
      BookmarkStore()
          .bookmarks(directory: dir.path)
          .map((bookmark) => bookmark.url),
      contains('https://third.example/'),
    );

    store.toggle(
      directory: dir.path,
      url: 'https://third.example/',
      title: 'Third',
    );
    expect(
      BookmarkStore()
          .bookmarks(directory: dir.path)
          .map((bookmark) => bookmark.url),
      isNot(contains('https://third.example/')),
    );

    store.toggle(directory: dir.path, url: 'https://example.com/', title: '');
    expect(
      BookmarkStore()
          .bookmarks(directory: dir.path)
          .map((bookmark) => bookmark.url),
      isNot(contains('https://example.com/')),
    );

    final freshDir = Directory.systemTemp.createTempSync('bookmarks_fresh');
    addTearDown(() => freshDir.deleteSync(recursive: true));
    expect(BookmarkStore().bookmarks(directory: freshDir.path).length, 3);
    expect(File('${freshDir.path}/Bookmarks.json').existsSync(), isTrue);
  });
}
