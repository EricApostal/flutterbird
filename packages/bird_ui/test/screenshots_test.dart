// Pictures of the gallery, a menu and a dialog, in both themes. Skipped unless
// asked for:
//
//   BIRD_UI_SHOTS=/some/directory flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bird_ui/bird_ui.dart';
import 'package:bird_ui/gallery.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

void main() {
  final directory = Platform.environment['BIRD_UI_SHOTS'];

  testWidgets(
    'screenshots',
    (tester) async {
      await tester.runAsync(() async {
        await _loadFont('.AppleSystemUIFont', '/System/Library/Fonts/SFNS.ttf');
        await _loadFont('Menlo', '/System/Library/Fonts/Menlo.ttc');
      });
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(1800, 2000);
      addTearDown(tester.view.reset);

      final boundary = GlobalKey();
      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$directory/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final mode in [BirdThemeMode.light, BirdThemeMode.dark]) {
        late BuildContext page;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: BirdApp(
              key: ValueKey(mode),
              themeMode: mode,
              home: Builder(
                builder: (context) {
                  page = context;
                  return const BirdGallery();
                },
              ),
            ),
          ),
        );
        await shot('gallery-${mode.name}');
        showBirdMenu(page, const Offset(420, 120), const [
          BirdMenuItem('New Tab', shortcut: '⌘T'),
          BirdMenuItem('New Window', shortcut: '⌘N'),
          BirdMenuItem.separator(),
          BirdMenuItem('Vertical Tabs', checked: true),
          BirdMenuItem('Paste', enabled: false, shortcut: '⌘V'),
          BirdMenuItem('More Tools', submenu: [BirdMenuItem('View Source')]),
          BirdMenuItem.separator(),
          BirdMenuItem('Settings'),
        ]).ignore();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await shot('menu-${mode.name}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        showBirdConfirm(
          page,
          title: 'Remove uBlock Origin?',
          message: 'Its settings are removed with it.',
          confirmLabel: 'Remove',
          destructive: true,
        ).ignore();
        await tester.pump();
        await shot('dialog-${mode.name}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pumpWidget(const SizedBox());
    },
    skip: directory == null,
  );
}
