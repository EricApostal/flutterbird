// Pictures of the settings page, one per section, in both themes. Skipped
// unless asked for:
//
//   SETTINGS_SHOTS=/some/directory flutter test test/settings_page_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ladybird/ladybird.dart';
import 'package:rubisco_browser/features/settings/engine_settings.dart';
import 'package:rubisco_browser/features/settings/settings_controller.dart';
import 'package:rubisco_browser/features/settings/settings_page.dart';

class _FakeSettings extends SettingsController {
  @override
  EngineSettings build() => EngineSettings(_snapshot);

  @override
  bool apply(Map<String, Object?> changes) => true;

  @override
  bool setConfigVariable(String name, Object? value) => true;

  @override
  void reload() {}
}

const Map<String, dynamic> _snapshot = {
  'newTabPageURL': 'about:newtab',
  'appearance': {
    'showMenuBar': false,
    'showBookmarksBar': 'never',
    'interfaceTheme': 'dark',
    'websiteColorScheme': 'system',
    'colorTheme': 'neutral',
  },
  'content': {'defaultZoomLevelFactor': 1.0, 'enableForceDark': false},
  'browsingBehavior': {'enableAutoscroll': true, 'enablePrimaryPaste': true},
  'searchEngine': {
    'engine': 'DuckDuckGo',
    'suggestions': false,
    'custom': [
      {'name': 'Wikipedia', 'url': 'https://en.wikipedia.org/w/index.php?search=%s'},
    ],
  },
  'autoplay': {'policy': 'block-audio'},
  'globalPrivacyControl': false,
  'contentBlockers': {'enabled': true},
  'backgroundNetworking': {
    'enabled': true,
    'features': {'contentBlockerSubscriptionUpdates': false},
  },
  'configVariables': {
    'debug.process.show_web_content_process_id': false,
    'network.http_cache.maximum_size_mb': 1024,
    'ui.tabs.vertical_tabs_hover_expand_delay_ms': 100,
  },
};

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

void main() {
  final directory = Platform.environment['SETTINGS_SHOTS'];
  if (directory == null) return;

  testWidgets('settings page shots', (tester) async {
    await tester.runAsync(() async {
      await _loadFont('.AppleSystemUIFont', '/System/Library/Fonts/SFNS.ttf');
      await _loadFont('Menlo', '/System/Library/Fonts/Menlo.ttc');
    });
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1600, 1500);
    addTearDown(tester.view.reset);

    final boundary = GlobalKey();
    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$directory/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final mode in [BirdThemeMode.dark, BirdThemeMode.light]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_FakeSettings.new),
            searchEnginesProvider.overrideWithValue(const [
              LadybirdSearchEngine(
                name: 'DuckDuckGo',
                queryUrl: 'https://duckduckgo.com/?q=%s',
              ),
              LadybirdSearchEngine(
                name: 'Wikipedia',
                queryUrl: 'https://en.wikipedia.org/w/index.php?search=%s',
              ),
            ]),
            configVariableDefinitionsProvider.overrideWithValue(const [
              LadybirdConfigVariableDefinition(
                name: 'debug.process.show_web_content_process_id',
                title: 'Show WebContent process ID in tab titles',
                description:
                    'Append the active WebContent process ID to each tab '
                    'title and tooltip.',
                defaultValue: false,
              ),
              LadybirdConfigVariableDefinition(
                name: 'network.http_cache.maximum_size_mb',
                title: 'Maximum disk cache size',
                description: 'Limit the space used for the HTTP disk cache, in MiB.',
                defaultValue: 1024,
              ),
            ]),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: BirdApp(
              key: ValueKey(mode),
              themeMode: mode,
              home: const SettingsPage(),
            ),
          ),
        ),
      );

      for (final section in ['Appearance', 'Search', 'Browsing', 'Content', 'Privacy', 'Advanced']) {
        await tester.tap(find.text(section).first);
        await shot('settings-${mode.name}-${section.toLowerCase()}');
      }
    }
  });
}
