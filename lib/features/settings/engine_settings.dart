/// One of the engine's custom search engines, as it stores it.
class EngineSearchEngine {
  const EngineSearchEngine({required this.name, required this.queryUrl});

  final String name;

  /// The query template, with `%s` where the search text goes.
  final String queryUrl;
}

/// The engine's settings, as one snapshot of
/// `WebView::Settings::serialize_json()`, read through the parts the settings
/// page shows.
///
/// The snapshot is the engine's own shape, not one invented here, so a
/// setting the engine adds needs no model change to be read.
class EngineSettings {
  const EngineSettings(this.raw);

  final Map<String, dynamic> raw;

  /// False until the engine has started and given a snapshot.
  bool get isLoaded => raw.isNotEmpty;

  dynamic _value(List<String> path) {
    dynamic value = raw;
    for (final key in path) {
      if (value is! Map) return null;
      value = value[key];
    }
    return value;
  }

  String? _string(List<String> path) {
    final value = _value(path);
    return value is String ? value : null;
  }

  bool _bool(List<String> path, {required bool fallback}) {
    final value = _value(path);
    return value is bool ? value : fallback;
  }

  num? _number(List<String> path) {
    final value = _value(path);
    return value is num ? value : null;
  }

  // Appearance

  /// `system`, `light` or `dark`.
  String get interfaceTheme =>
      _string(['appearance', 'interfaceTheme']) ?? 'system';

  /// `system`, `light` or `dark`.
  String get websiteColorScheme =>
      _string(['appearance', 'websiteColorScheme']) ?? 'system';

  // Search

  /// The chosen engine's name, or null when the engine's default is used.
  String? get searchEngineName => _string(['searchEngine', 'engine']);

  List<EngineSearchEngine> get customSearchEngines {
    final custom = _value(['searchEngine', 'custom']);
    if (custom is! List) return const [];
    return [
      for (final engine in custom)
        if (engine is Map &&
            engine['name'] is String &&
            engine['url'] is String)
          EngineSearchEngine(
            name: engine['name'] as String,
            queryUrl: engine['url'] as String,
          ),
    ];
  }

  // Browsing

  /// `allow-audio-and-video`, `block-audio` or `block-audio-and-video`.
  String get autoplayPolicy =>
      _string(['autoplay', 'policy']) ?? 'block-audio';

  bool get autoscroll =>
      _bool(['browsingBehavior', 'enableAutoscroll'], fallback: true);

  bool get primaryPaste =>
      _bool(['browsingBehavior', 'enablePrimaryPaste'], fallback: true);

  // Content

  double get defaultZoomLevelFactor =>
      _number(['content', 'defaultZoomLevelFactor'])?.toDouble() ?? 1.0;

  bool get forceDark =>
      _bool(['content', 'enableForceDark'], fallback: false);

  // Privacy

  bool get globalPrivacyControl =>
      _bool(['globalPrivacyControl'], fallback: false);

  bool get contentBlockerEnabled =>
      _bool(['contentBlockers', 'enabled'], fallback: false);

  bool get backgroundNetworkingEnabled =>
      _bool(['backgroundNetworking', 'enabled'], fallback: true);

  bool get filterListUpdatesEnabled => _bool([
    'backgroundNetworking',
    'features',
    'contentBlockerSubscriptionUpdates',
  ], fallback: false);

  // Advanced

  /// The current value of a config variable, or null when the snapshot does
  /// not carry it.
  dynamic configVariable(String name) {
    final variables = _value(['configVariables']);
    return variables is Map ? variables[name] : null;
  }
}
