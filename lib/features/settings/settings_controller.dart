import 'package:bird_ui/bird_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:rubisco_browser/features/settings/engine_settings.dart';
import 'package:rubisco_browser/features/theme/appearance.dart';

/// The engine's settings, which every window and tab shares.
///
/// The engine keeps them in one process-wide [WebView::Settings], so this
/// reads and writes them through [LadybirdController]'s process-wide methods
/// rather than any one tab's.
class SettingsController extends Notifier<EngineSettings> {
  @override
  EngineSettings build() =>
      EngineSettings(LadybirdController.settingsSnapshot());

  /// Re-reads the snapshot, for a change made outside this controller, such
  /// as the engine's own first-run defaults.
  void reload() =>
      state = EngineSettings(LadybirdController.settingsSnapshot());

  /// Applies [changes] to the engine's settings and re-reads them: maps merge
  /// into the ones they name, and a null removes a key. Returns whether the
  /// engine took the change.
  bool apply(Map<String, Object?> changes) {
    if (!LadybirdController.applySettingsChanges(changes)) return false;
    reload();
    return true;
  }

  /// Sets one config variable and re-reads the settings. Returns whether the
  /// engine knows the variable; an invalid value for a known one is dropped
  /// by the engine, as on its own settings page.
  bool setConfigVariable(String name, Object? value) {
    if (!LadybirdController.setConfigVariableValue(name, value)) return false;
    reload();
    return true;
  }
}

final settingsProvider = NotifierProvider<SettingsController, EngineSettings>(
  SettingsController.new,
);

/// Every search engine the engine knows about: its builtins, then the custom
/// ones. Re-read when [settingsProvider] changes, since adding or removing an
/// engine goes through it.
final searchEnginesProvider = Provider<List<LadybirdSearchEngine>>((ref) {
  ref.watch(settingsProvider.select((s) => s.customSearchEngines.length));
  return LadybirdController.searchEngines();
});

/// The engine's generic config variables: name, title, description and
/// default, for the settings page to show without knowing any of them.
final configVariableDefinitionsProvider =
    Provider<List<LadybirdConfigVariableDefinition>>(
      (ref) => LadybirdController.configVariableDefinitions(),
    );

/// The interface theme the engine has stored, for the app's own chrome.
final interfaceThemeModeProvider = Provider<BirdThemeMode>((ref) {
  final theme = ref.watch(settingsProvider.select((s) => s.interfaceTheme));
  return switch (theme) {
    'light' => BirdThemeMode.light,
    'dark' => BirdThemeMode.dark,
    'system' => BirdThemeMode.system,
    _ => desktopThemeMode,
  };
});
