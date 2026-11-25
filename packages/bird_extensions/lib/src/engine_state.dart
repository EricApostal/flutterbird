import 'dart:convert';
import 'dart:io';

import 'extension_registry.dart';
import 'host/misc_apis.dart' show DynamicContentScript;
import 'json_util.dart';
import 'localization.dart';
import 'manifest.dart';
import 'match_pattern.dart';
import 'shim/shim_source.dart';

/// Builds the state that every web content process holds so that it can run
/// content scripts: which extensions there are, where their scripts apply, the
/// scripts' source, and the shim that gives them `browser`.
///
/// The processes decide what to inject without asking, because `document_start`
/// scripts must run before the page does anything, so everything they need is
/// in this document. Its format is shared with the engine's ExtensionRuntime.
class EngineStateBuilder {
  EngineStateBuilder({
    required this.registry,
    this.uiLanguage = 'en-US',
    this.platform = 'mac',
    this.browserVersion = '1.0',
    this.shim = browserShimSource,
    this.dynamicScripts,
    this.interceptRequests,
  });

  final ExtensionRegistry registry;
  final String uiLanguage;

  /// `mac`, `win`, `linux`, `android`: what `runtime.getPlatformInfo` reports.
  final String platform;
  final String browserVersion;
  final String shim;

  /// Whether an extension wants to see requests before they are sent. The web
  /// content processes only hold requests for the extensions when this is true,
  /// so a browser with no request-blocking extension pays nothing.
  final bool Function()? interceptRequests;

  /// Content scripts extensions registered while running, by extension uuid.
  final Iterable<DynamicContentScript> Function(String uuid)? dynamicScripts;

  Future<String> build() async {
    final extensions = <Map<String, Object?>>[];

    for (final extension in registry.extensions) {
      if (!extension.enabled || extension.type != ExtensionType.extension) {
        continue;
      }
      final entry = await _entryFor(extension);
      if (entry != null) extensions.add(entry);
    }

    return jsonEncode({
      // Where extensions are unpacked, so the browser can serve their files.
      'installedRoot': '${registry.root.path}/installed',
      'interceptRequests': interceptRequests?.call() ?? false,
      'shim': shim,
      'extensions': extensions,
    });
  }

  Future<Map<String, Object?>?> _entryFor(InstalledExtension extension) async {
    final directory = registry.directoryFor(extension);

    final Manifest manifest;
    try {
      manifest = Manifest.parseBytes(
        await File('${directory.path}/manifest.json').readAsBytes(),
      ).manifest;
    } on Object {
      // A broken or missing install is skipped, not allowed to stop the rest.
      return null;
    }

    final catalog = await _readCatalog(directory, manifest);

    final granted = [
      for (final origin in extension.grantedOrigins)
        ?MatchPattern.tryParse(origin),
    ];

    final scripts = <Map<String, Object?>>[];
    for (final script in manifest.contentScripts) {
      // A content script runs only where the extension has been granted access.
      final matches = [
        for (final source in script.matches)
          if (_isGranted(source, granted)) source,
      ];
      if (matches.isEmpty) continue;

      final js = await _readFiles(directory, script.js);
      final css = await _readFiles(directory, script.css);
      if (js.isEmpty && css.isEmpty) continue;

      scripts.add({
        'matches': matches,
        'excludeMatches': script.excludeMatches,
        'includeGlobs': script.includeGlobs,
        'excludeGlobs': script.excludeGlobs,
        'runAt': script.runAt.wireName,
        'allFrames': script.allFrames,
        'matchAboutBlank': script.matchAboutBlank,
        'world': script.world == ContentScriptWorld.main ? 'MAIN' : 'ISOLATED',
        'js': js,
        'css': css,
      });
    }

    var dynamicIndex = 0;
    for (final registered
        in dynamicScripts?.call(extension.uuid) ??
            const <DynamicContentScript>[]) {
      final script = await _dynamicScript(
        directory,
        registered,
        dynamicIndex++,
      );
      if (script != null) scripts.add(script);
    }

    final shown = Map<String, Object?>.of(manifest.raw)
      ..['name'] = catalog.localize(manifest.name)
      ..['description'] = manifest.description == null
          ? null
          : catalog.localize(manifest.description!);

    final init = {
      'id': extension.id,
      'uuid': extension.uuid,
      'baseUrl': '${extension.origin}/',
      'manifest': shown,
      'manifestVersion': extension.manifestVersion,
      'messages': catalog.shimEntries(),
      'uiLanguage': uiLanguage,
      'platform': platform,
      'browserVersion': browserVersion,
      'contextType': 'content_script',
    };

    return {
      'uuid': extension.uuid,
      'id': extension.id,
      // A string, because the engine pastes it into `__bird_init = <this>;`.
      'init': jsonEncode(init),
      'contentScripts': scripts,
      // The hosts the extension was granted, which its own pages may read from
      // without CORS.
      'hostPermissions': extension.grantedOrigins,
      // What web pages may load from the extension.
      'webAccessible': [
        for (final rule in manifest.webAccessibleResources)
          {'resources': rule.resources, 'matches': rule.matches},
      ],
    };
  }

  /// A script registered with `contentScripts.register`, whose scripts and
  /// stylesheets are given as files of the extension or as code.
  Future<Map<String, Object?>?> _dynamicScript(
    Directory directory,
    DynamicContentScript registered,
    int index,
  ) async {
    final options = registered.options;

    List<String> strings(Object? value) =>
        value is List ? value.whereType<String>().toList() : const [];

    Future<List<Map<String, String>>> sources(
      Object? entries,
      String extension,
    ) async {
      final result = <Map<String, String>>[];
      var n = 0;
      for (final entry in entries is List ? entries : const []) {
        if (entry is! Map) continue;
        final code = entry['code'];
        final file = entry['file'];
        if (code is String) {
          result.add({
            'path': 'registered-$index-${n++}.$extension',
            'source': code,
          });
        } else if (file is String) {
          final path = normalizeResourcePath(file);
          if (path == null) continue;
          result.addAll(await _readFiles(directory, [path]));
        }
      }
      return result;
    }

    final matches = strings(options['matches']);
    final js = await sources(options['js'], 'js');
    final css = await sources(options['css'], 'css');
    if (matches.isEmpty || (js.isEmpty && css.isEmpty)) return null;

    return {
      'matches': matches,
      'excludeMatches': strings(options['excludeMatches']),
      'includeGlobs': strings(options['includeGlobs']),
      'excludeGlobs': strings(options['excludeGlobs']),
      'runAt': options['runAt'] is String ? options['runAt'] : 'document_idle',
      'allFrames': options['allFrames'] == true,
      'matchAboutBlank': options['matchAboutBlank'] == true,
      'world': 'ISOLATED',
      'js': js,
      'css': css,
    };
  }

  static bool _isGranted(String source, List<MatchPattern> granted) {
    final wanted = MatchPattern.tryParse(source);
    if (wanted == null) return false;
    return granted.any((grant) => grant.covers(wanted));
  }

  Future<List<Map<String, String>>> _readFiles(
    Directory directory,
    List<String> paths,
  ) async {
    final files = <Map<String, String>>[];
    for (final path in paths) {
      final file = File('${directory.path}/$path');
      try {
        files.add({
          'path': path,
          'source': utf8.decode(await file.readAsBytes(), allowMalformed: true),
        });
      } on FileSystemException {
        // The installer already warned about a file the manifest names but
        // the package lacks.
      }
    }
    return files;
  }

  Future<MessageCatalog> _readCatalog(
    Directory directory,
    Manifest manifest,
  ) async {
    final locales = Directory('${directory.path}/_locales');
    if (!await locales.exists()) return MessageCatalog.empty;

    final available = [
      await for (final entity in locales.list())
        if (entity is Directory)
          entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    ];
    final locale = chooseLocale(
      available: available,
      preferred: [uiLanguage, 'en'],
      defaultLocale: manifest.defaultLocale,
    );
    if (locale == null) return MessageCatalog.empty;

    try {
      final bytes = await File(
        '${locales.path}/$locale/messages.json',
      ).readAsBytes();
      return MessageCatalog.fromJson(decodeLenientJson(bytes));
    } on Object {
      return MessageCatalog.empty;
    }
  }
}
