import 'package:bird_ui/bird_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubisco_browser/features/settings/engine_settings.dart';
import 'package:rubisco_browser/features/settings/settings_controller.dart';
import 'package:rubisco_browser/features/theme/appearance.dart';

/// Settings as the engine reports them, without an engine.
class _StubSettings extends SettingsController {
  _StubSettings(this.snapshot);

  final Map<String, dynamic> snapshot;

  @override
  EngineSettings build() => EngineSettings(snapshot);

  @override
  void reload() {}
}

ProviderContainer _containerWith(String? interfaceTheme) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _StubSettings({
          if (interfaceTheme != null) 'appearance': {'interfaceTheme': interfaceTheme},
        }),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the stored interface theme is what the interface is drawn in', () {
    expect(
      _containerWith('light').read(interfaceThemeModeProvider),
      BirdThemeMode.light,
    );
    expect(
      _containerWith('dark').read(interfaceThemeModeProvider),
      BirdThemeMode.dark,
    );
    expect(
      _containerWith('system').read(interfaceThemeModeProvider),
      BirdThemeMode.system,
    );
  });

  test('an engine with no preference follows the system', () {
    // The engine's own default is "system", so an app whose settings say
    // nothing follows the system too.
    expect(_containerWith(null).read(interfaceThemeModeProvider), BirdThemeMode.system);
  });

  test('a theme the app does not know keeps its own', () {
    expect(_containerWith('chartreuse').read(interfaceThemeModeProvider), desktopThemeMode);
  });

  test('settings are read from the engine snapshot by the names it stores them under', () {
    const settings = EngineSettings({
      'appearance': {'interfaceTheme': 'light', 'websiteColorScheme': 'dark'},
      'searchEngine': {
        'engine': 'Wikipedia',
        'custom': [
          {'name': 'Wikipedia', 'url': 'https://en.wikipedia.org/w/index.php?search=%s'},
        ],
      },
      'autoplay': {'policy': 'block-audio-and-video'},
      'browsingBehavior': {'enableAutoscroll': false, 'enablePrimaryPaste': true},
      'content': {'defaultZoomLevelFactor': 1.25, 'enableForceDark': true},
      'globalPrivacyControl': true,
      'contentBlockers': {'enabled': false},
      'backgroundNetworking': {
        'enabled': false,
        'features': {'contentBlockerSubscriptionUpdates': true},
      },
      'configVariables': {'network.http_cache.maximum_size_mb': 512},
    });

    expect(settings.isLoaded, isTrue);
    expect(settings.interfaceTheme, 'light');
    expect(settings.websiteColorScheme, 'dark');
    expect(settings.searchEngineName, 'Wikipedia');
    expect(settings.customSearchEngines.single.queryUrl, contains('%s'));
    expect(settings.autoplayPolicy, 'block-audio-and-video');
    expect(settings.autoscroll, isFalse);
    expect(settings.primaryPaste, isTrue);
    expect(settings.defaultZoomLevelFactor, 1.25);
    expect(settings.forceDark, isTrue);
    expect(settings.globalPrivacyControl, isTrue);
    expect(settings.contentBlockerEnabled, isFalse);
    expect(settings.backgroundNetworkingEnabled, isFalse);
    expect(settings.filterListUpdatesEnabled, isTrue);
    expect(settings.configVariable('network.http_cache.maximum_size_mb'), 512);
  });

  test('an empty snapshot is not mistaken for settings', () {
    const settings = EngineSettings({});
    expect(settings.isLoaded, isFalse);
    expect(settings.interfaceTheme, 'system');
    expect(settings.customSearchEngines, isEmpty);
  });
}
