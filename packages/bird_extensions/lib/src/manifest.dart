import 'dart:convert';

import 'json_util.dart';
import 'match_pattern.dart';
import 'permissions.dart' show isKnownPermission;
import 'xpi_extractor.dart' show safeRelativePath;

/// A manifest that cannot be used at all: not JSON, or missing the fields
/// every extension needs.
class ManifestException implements Exception {
  ManifestException(this.message);

  final String message;

  @override
  String toString() => 'ManifestException: $message';
}

enum ExtensionType { extension, theme, dictionary, langpack }

enum RunAt {
  documentStart('document_start'),
  documentEnd('document_end'),
  documentIdle('document_idle');

  const RunAt(this.wireName);

  final String wireName;

  static RunAt parse(String? value) => RunAt.values.firstWhere(
    (candidate) => candidate.wireName == value,
    orElse: () => RunAt.documentIdle,
  );
}

enum ContentScriptWorld { isolated, main }

/// Which of the three toolbar surfaces a spec was declared for.
enum ActionKind { action, browserAction, pageAction }

/// Turns a manifest path such as `/icons/a.png` or `./b.js` into a path
/// relative to the extension root, or null if it would leave the root.
String? normalizeResourcePath(String path) {
  var cleaned = path;
  while (cleaned.startsWith('/')) {
    cleaned = cleaned.substring(1);
  }
  return safeRelativePath(cleaned);
}

/// Picks the entry of a size → path [icons] map to show at [size] pixels:
/// the smallest one at least that big, else the largest available. The key
/// `any` (used when the manifest gave one path for every size) always fits.
String? bestIconPath(Map<String, String> icons, int size) {
  if (icons.isEmpty) return null;
  final any = icons['any'];
  if (any != null) return any;

  final sized = <int, String>{};
  for (final entry in icons.entries) {
    final key = int.tryParse(entry.key);
    if (key != null) sized[key] = entry.value;
  }
  if (sized.isEmpty) return icons.values.first;

  final sizes = sized.keys.toList()..sort();
  for (final candidate in sizes) {
    if (candidate >= size) return sized[candidate];
  }
  return sized[sizes.last];
}

class ContentScript {
  const ContentScript({
    required this.matches,
    this.excludeMatches = const [],
    this.includeGlobs = const [],
    this.excludeGlobs = const [],
    this.js = const [],
    this.css = const [],
    this.runAt = RunAt.documentIdle,
    this.allFrames = false,
    this.matchAboutBlank = false,
    this.matchOriginAsFallback = false,
    this.world = ContentScriptWorld.isolated,
    this.cssOrigin = 'author',
  });

  final List<String> matches;
  final List<String> excludeMatches;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final List<String> js;
  final List<String> css;
  final RunAt runAt;
  final bool allFrames;
  final bool matchAboutBlank;
  final bool matchOriginAsFallback;
  final ContentScriptWorld world;

  /// `author` or `user`; `user` styles can override the page's own.
  final String cssOrigin;

  Map<String, Object?> toJson() => {
    'matches': matches,
    'exclude_matches': excludeMatches,
    'include_globs': includeGlobs,
    'exclude_globs': excludeGlobs,
    'js': js,
    'css': css,
    'run_at': runAt.wireName,
    'all_frames': allFrames,
    'match_about_blank': matchAboutBlank,
    'match_origin_as_fallback': matchOriginAsFallback,
    'world': world == ContentScriptWorld.main ? 'MAIN' : 'ISOLATED',
    'css_origin': cssOrigin,
  };
}

class BackgroundSpec {
  const BackgroundSpec({
    this.scripts = const [],
    this.page,
    this.serviceWorker,
    this.persistent = false,
    this.isModule = false,
  });

  final List<String> scripts;
  final String? page;

  /// Declared by Chrome-first MV3 extensions. Firefox ignores it when
  /// [scripts] or [page] is also given, and so does this.
  final String? serviceWorker;

  /// MV2 backgrounds are persistent unless they say otherwise; MV3 ones are
  /// event pages and never are.
  final bool persistent;
  final bool isModule;

  /// True when there is something to run in the background.
  bool get isRunnable => scripts.isNotEmpty || page != null;
}

class ActionSpec {
  const ActionSpec({
    required this.kind,
    this.defaultTitle,
    this.defaultPopup,
    this.defaultIcon = const {},
    this.browserStyle = false,
    this.showMatches = const [],
  });

  final ActionKind kind;
  final String? defaultTitle;
  final String? defaultPopup;

  /// Size → path; a single path becomes `{'any': path}`.
  final Map<String, String> defaultIcon;
  final bool browserStyle;

  /// `page_action` only: the patterns for which the icon is shown.
  final List<String> showMatches;
}

class OptionsUiSpec {
  const OptionsUiSpec({
    required this.page,
    this.openInTab = false,
    this.browserStyle = false,
  });

  final String page;
  final bool openInTab;
  final bool browserStyle;
}

class SidebarActionSpec {
  const SidebarActionSpec({
    required this.defaultPanel,
    this.defaultTitle,
    this.defaultIcon = const {},
    this.openAtInstall = true,
  });

  final String defaultPanel;
  final String? defaultTitle;
  final Map<String, String> defaultIcon;
  final bool openAtInstall;
}

class WebAccessibleResource {
  const WebAccessibleResource({
    required this.resources,
    this.matches = const [],
    this.extensionIds = const [],
  });

  final List<String> resources;
  final List<String> matches;
  final List<String> extensionIds;
}

class CommandSpec {
  const CommandSpec({
    required this.name,
    this.description,
    this.suggestedKey = const {},
  });

  final String name;
  final String? description;

  /// Platform (`default`, `mac`, `linux`, `windows`) → shortcut.
  final Map<String, String> suggestedKey;
}

class DnrRuleResource {
  const DnrRuleResource({
    required this.id,
    required this.path,
    required this.enabled,
  });

  final String id;
  final String path;
  final bool enabled;
}

class GeckoSettings {
  const GeckoSettings({
    this.id,
    this.strictMinVersion,
    this.strictMaxVersion,
    this.updateUrl,
    this.requiredDataCollection = const [],
    this.optionalDataCollection = const [],
  });

  final String? id;
  final String? strictMinVersion;
  final String? strictMaxVersion;
  final String? updateUrl;
  final List<String> requiredDataCollection;
  final List<String> optionalDataCollection;
}

class ContentSecurityPolicy {
  const ContentSecurityPolicy({required this.extensionPages, this.sandbox});

  /// The policy for the extension's own pages (background, popup, options).
  final String extensionPages;
  final String? sandbox;

  static const String defaultMv2 =
      "script-src 'self' 'wasm-unsafe-eval'; object-src 'self';";
  static const String defaultMv3 =
      "script-src 'self' 'wasm-unsafe-eval'; upgrade-insecure-requests;";
}

/// The result of reading a `manifest.json`: the manifest, plus anything in
/// it that was ignored. Firefox is forgiving about unknown or malformed
/// optional keys, so this is as well.
class ManifestParseResult {
  const ManifestParseResult(this.manifest, this.warnings);

  final Manifest manifest;
  final List<String> warnings;
}

class Manifest {
  Manifest._({
    required this.raw,
    required this.manifestVersion,
    required this.type,
    required this.name,
    required this.version,
    required this.description,
    required this.defaultLocale,
    required this.icons,
    required this.gecko,
    required this.permissions,
    required this.hostPermissions,
    required this.optionalPermissions,
    required this.optionalHostPermissions,
    required this.contentScripts,
    required this.background,
    required this.action,
    required this.pageAction,
    required this.options,
    required this.sidebar,
    required this.webAccessibleResources,
    required this.commands,
    required this.contentSecurityPolicy,
    required this.dnrRuleResources,
    required this.chromeUrlOverrides,
    required this.devtoolsPage,
    required this.omniboxKeyword,
    required this.incognito,
    required this.homepageUrl,
    required this.author,
  });

  /// The manifest exactly as parsed, for keys this model does not look at.
  final Map<String, Object?> raw;

  final int manifestVersion;
  final ExtensionType type;

  /// The `name` and `description` as written, which may be `__MSG_x__`
  /// references until they are run through a message catalog.
  final String name;
  final String version;
  final String? description;
  final String? defaultLocale;

  final Map<String, String> icons;
  final GeckoSettings? gecko;

  /// API permissions such as `tabs` or `storage`. Host patterns are in
  /// [hostPermissions], never here.
  final List<String> permissions;

  /// Host patterns from `host_permissions` and, in MV2, from `permissions`.
  final List<String> hostPermissions;
  final List<String> optionalPermissions;
  final List<String> optionalHostPermissions;

  final List<ContentScript> contentScripts;
  final BackgroundSpec? background;

  /// `action` in MV3, `browser_action` in MV2.
  final ActionSpec? action;
  final ActionSpec? pageAction;
  final OptionsUiSpec? options;
  final SidebarActionSpec? sidebar;
  final List<WebAccessibleResource> webAccessibleResources;
  final List<CommandSpec> commands;
  final ContentSecurityPolicy contentSecurityPolicy;
  final List<DnrRuleResource> dnrRuleResources;

  /// `newtab`, `history` or `bookmarks` → page.
  final Map<String, String> chromeUrlOverrides;
  final String? devtoolsPage;
  final String? omniboxKeyword;
  final String incognito;
  final String? homepageUrl;
  final String? author;

  /// The extension id the manifest declares, if it declares one.
  String? get id => gecko?.id;

  bool get isManifestV3 => manifestVersion == 3;

  /// Every pattern a content script asks to run on. MV2 prompts list these
  /// as host access alongside [hostPermissions].
  List<String> get contentScriptMatches => [
    for (final script in contentScripts) ...script.matches,
  ];

  static ManifestParseResult parseBytes(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = decodeLenientJson(bytes);
    } on FormatException catch (error) {
      throw ManifestException(
        'manifest.json is not valid JSON: ${error.message}',
      );
    }
    return _parseObject(decoded);
  }

  static ManifestParseResult parse(String source) =>
      parseBytes(utf8.encode(source));

  static ManifestParseResult _parseObject(Object? decoded) {
    if (decoded is! Map) {
      throw ManifestException('manifest.json must contain a JSON object');
    }
    final json = decoded.cast<String, Object?>();
    final warnings = <String>[];
    final reader = _Reader(json, '', warnings);

    final manifestVersion = json['manifest_version'];
    if (manifestVersion is! int ||
        (manifestVersion != 2 && manifestVersion != 3)) {
      throw ManifestException(
        '"manifest_version" must be 2 or 3 (got ${jsonEncode(manifestVersion)})',
      );
    }

    final name = reader.string('name');
    if (name == null || name.trim().isEmpty) {
      throw ManifestException('"name" is missing or empty');
    }

    final version = reader.string('version');
    if (version == null ||
        !RegExp(r'^[0-9A-Za-z.+*_-]{1,100}$').hasMatch(version)) {
      throw ManifestException('"version" is missing or not a valid version');
    }

    final type = json.containsKey('theme')
        ? ExtensionType.theme
        : json.containsKey('dictionaries')
        ? ExtensionType.dictionary
        : json.containsKey('langpack_id')
        ? ExtensionType.langpack
        : ExtensionType.extension;

    final gecko = _parseGecko(json, warnings);

    // MV2 lists host patterns inside "permissions"; MV3 moves them to
    // "host_permissions". Firefox accepts patterns in either, so both are
    // sorted the same way here.
    final apiPermissions = <String>[];
    final hosts = <String>[];
    _splitPermissions(
      reader.strings('permissions'),
      apiPermissions,
      hosts,
      warnings,
    );
    _splitPermissions(
      reader.strings('host_permissions'),
      apiPermissions,
      hosts,
      warnings,
    );

    final optionalApi = <String>[];
    final optionalHosts = <String>[];
    _splitPermissions(
      reader.strings('optional_permissions'),
      optionalApi,
      optionalHosts,
      warnings,
    );
    _splitPermissions(
      reader.strings('optional_host_permissions'),
      optionalApi,
      optionalHosts,
      warnings,
    );

    final actionKey = manifestVersion == 3 ? 'action' : 'browser_action';

    return ManifestParseResult(
      Manifest._(
        raw: json,
        manifestVersion: manifestVersion,
        type: type,
        name: name,
        version: version,
        description: reader.string('description'),
        defaultLocale: reader.string('default_locale'),
        icons: _parseIconMap(json['icons'], warnings, 'icons'),
        gecko: gecko,
        permissions: _unique(apiPermissions),
        hostPermissions: _unique(hosts),
        optionalPermissions: _unique(optionalApi),
        optionalHostPermissions: _unique(optionalHosts),
        contentScripts: _parseContentScripts(json['content_scripts'], warnings),
        background: _parseBackground(
          json['background'],
          manifestVersion,
          warnings,
        ),
        action: _parseAction(
          json[actionKey],
          manifestVersion == 3 ? ActionKind.action : ActionKind.browserAction,
          warnings,
        ),
        pageAction: _parseAction(
          json['page_action'],
          ActionKind.pageAction,
          warnings,
        ),
        options: _parseOptions(json, warnings),
        sidebar: _parseSidebar(json['sidebar_action'], warnings),
        webAccessibleResources: _parseWebAccessible(
          json['web_accessible_resources'],
          manifestVersion,
          warnings,
        ),
        commands: _parseCommands(json['commands'], warnings),
        contentSecurityPolicy: _parseCsp(
          json['content_security_policy'],
          manifestVersion,
        ),
        dnrRuleResources: _parseDnr(json['declarative_net_request'], warnings),
        chromeUrlOverrides: _parseStringMap(json['chrome_url_overrides']),
        devtoolsPage: reader.string('devtools_page'),
        omniboxKeyword: _parseOmnibox(json['omnibox']),
        incognito: reader.string('incognito') ?? 'spanning',
        homepageUrl: reader.string('homepage_url'),
        author: reader.string('author'),
      ),
      warnings,
    );
  }

  static List<String> _unique(List<String> values) => values.toSet().toList();

  static void _splitPermissions(
    List<String> values,
    List<String> api,
    List<String> hosts,
    List<String> warnings,
  ) {
    for (final value in values) {
      if (value == '<all_urls>' || value.contains('://')) {
        if (MatchPattern.tryParse(value) == null) {
          warnings.add('Ignoring invalid host permission "$value"');
        } else {
          hosts.add(value);
        }
      } else {
        // Kept even when unknown: the list here may trail Firefox's, and
        // dropping a real permission would silently break the extension.
        if (!isKnownPermission(value)) {
          warnings.add('Unknown permission "$value"');
        }
        api.add(value);
      }
    }
  }

  static GeckoSettings? _parseGecko(
    Map<String, Object?> json,
    List<String> warnings,
  ) {
    // "applications" is the old name for "browser_specific_settings".
    final settings = json['browser_specific_settings'] ?? json['applications'];
    if (settings is! Map) return null;
    final gecko = settings['gecko'];
    if (gecko is! Map) return null;

    final reader = _Reader(gecko.cast<String, Object?>(), 'gecko.', warnings);
    final collection = gecko['data_collection_permissions'];
    return GeckoSettings(
      id: reader.string('id'),
      strictMinVersion: reader.string('strict_min_version'),
      strictMaxVersion: reader.string('strict_max_version'),
      updateUrl: reader.string('update_url'),
      requiredDataCollection: collection is Map
          ? _Reader(
              collection.cast<String, Object?>(),
              'gecko.data_collection_permissions.',
              warnings,
            ).strings('required')
          : const [],
      optionalDataCollection: collection is Map
          ? _Reader(
              collection.cast<String, Object?>(),
              'gecko.data_collection_permissions.',
              warnings,
            ).strings('optional')
          : const [],
    );
  }

  static Map<String, String> _parseIconMap(
    Object? value,
    List<String> warnings,
    String where,
  ) {
    if (value is String) {
      final path = normalizeResourcePath(value);
      if (path == null) {
        warnings.add('Ignoring unsafe icon path in $where');
        return const {};
      }
      return {'any': path};
    }
    if (value is! Map) return const {};

    final icons = <String, String>{};
    for (final entry in value.entries) {
      final path = entry.value;
      if (path is! String) continue;
      final normalized = normalizeResourcePath(path);
      if (normalized == null) {
        warnings.add('Ignoring unsafe icon path "$path" in $where');
        continue;
      }
      icons[entry.key.toString()] = normalized;
    }
    return icons;
  }

  static List<ContentScript> _parseContentScripts(
    Object? value,
    List<String> warnings,
  ) {
    if (value == null) return const [];
    if (value is! List) {
      warnings.add('"content_scripts" must be an array');
      return const [];
    }

    final scripts = <ContentScript>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      final where = 'content_scripts[$index]';
      if (item is! Map) {
        warnings.add('$where is not an object');
        continue;
      }

      final reader = _Reader(item.cast<String, Object?>(), '$where.', warnings);

      List<String> patterns(String key) {
        final kept = <String>[];
        for (final pattern in reader.strings(key)) {
          if (MatchPattern.tryParse(pattern) == null) {
            warnings.add('$where.$key: ignoring invalid pattern "$pattern"');
          } else {
            kept.add(pattern);
          }
        }
        return kept;
      }

      List<String> files(String key) {
        final kept = <String>[];
        for (final file in reader.strings(key)) {
          final path = normalizeResourcePath(file);
          if (path == null) {
            warnings.add('$where.$key: ignoring unsafe path "$file"');
          } else {
            kept.add(path);
          }
        }
        return kept;
      }

      final matches = patterns('matches');
      if (matches.isEmpty) {
        warnings.add('$where has no valid "matches"; skipping it');
        continue;
      }

      final js = files('js');
      final css = files('css');
      if (js.isEmpty && css.isEmpty) {
        warnings.add('$where has neither "js" nor "css"; skipping it');
        continue;
      }

      scripts.add(
        ContentScript(
          matches: matches,
          excludeMatches: patterns('exclude_matches'),
          includeGlobs: reader.strings('include_globs'),
          excludeGlobs: reader.strings('exclude_globs'),
          js: js,
          css: css,
          runAt: RunAt.parse(reader.string('run_at')),
          allFrames: reader.boolean('all_frames') ?? false,
          matchAboutBlank: reader.boolean('match_about_blank') ?? false,
          matchOriginAsFallback:
              reader.boolean('match_origin_as_fallback') ?? false,
          world: reader.string('world')?.toUpperCase() == 'MAIN'
              ? ContentScriptWorld.main
              : ContentScriptWorld.isolated,
          cssOrigin: reader.string('css_origin') == 'user' ? 'user' : 'author',
        ),
      );
    }
    return scripts;
  }

  static BackgroundSpec? _parseBackground(
    Object? value,
    int manifestVersion,
    List<String> warnings,
  ) {
    if (value is! Map) return null;
    final reader = _Reader(
      value.cast<String, Object?>(),
      'background.',
      warnings,
    );

    final scripts = <String>[];
    for (final script in reader.strings('scripts')) {
      final path = normalizeResourcePath(script);
      if (path == null) {
        warnings.add('background.scripts: ignoring unsafe path "$script"');
      } else {
        scripts.add(path);
      }
    }

    final pageValue = reader.string('page');
    final page = pageValue == null ? null : normalizeResourcePath(pageValue);

    final persistent = reader.boolean('persistent');
    if (manifestVersion == 3 && persistent == true) {
      warnings.add('background.persistent is ignored in Manifest V3');
    }

    return BackgroundSpec(
      scripts: scripts,
      page: page,
      serviceWorker: reader.string('service_worker'),
      persistent: manifestVersion == 3 ? false : (persistent ?? true),
      isModule: reader.string('type') == 'module',
    );
  }

  static ActionSpec? _parseAction(
    Object? value,
    ActionKind kind,
    List<String> warnings,
  ) {
    if (value is! Map) return null;
    final reader = _Reader(
      value.cast<String, Object?>(),
      '${kind.name}.',
      warnings,
    );

    final popup = reader.string('default_popup');
    return ActionSpec(
      kind: kind,
      defaultTitle: reader.string('default_title'),
      defaultPopup: popup == null ? null : normalizeResourcePath(popup),
      defaultIcon: _parseIconMap(
        value['default_icon'],
        warnings,
        '${kind.name}.default_icon',
      ),
      browserStyle: reader.boolean('browser_style') ?? false,
      showMatches: reader.strings('show_matches'),
    );
  }

  static OptionsUiSpec? _parseOptions(
    Map<String, Object?> json,
    List<String> warnings,
  ) {
    final ui = json['options_ui'];
    if (ui is Map) {
      final reader = _Reader(
        ui.cast<String, Object?>(),
        'options_ui.',
        warnings,
      );
      final page = reader.string('page');
      final path = page == null ? null : normalizeResourcePath(page);
      if (path != null) {
        return OptionsUiSpec(
          page: path,
          openInTab: reader.boolean('open_in_tab') ?? false,
          browserStyle: reader.boolean('browser_style') ?? false,
        );
      }
    }

    // The older single-key form always opens in a tab.
    final legacy = json['options_page'];
    if (legacy is String) {
      final path = normalizeResourcePath(legacy);
      if (path != null) return OptionsUiSpec(page: path, openInTab: true);
    }
    return null;
  }

  static SidebarActionSpec? _parseSidebar(
    Object? value,
    List<String> warnings,
  ) {
    if (value is! Map) return null;
    final reader = _Reader(
      value.cast<String, Object?>(),
      'sidebar_action.',
      warnings,
    );
    final panel = reader.string('default_panel');
    final path = panel == null ? null : normalizeResourcePath(panel);
    if (path == null) return null;

    return SidebarActionSpec(
      defaultPanel: path,
      defaultTitle: reader.string('default_title'),
      defaultIcon: _parseIconMap(
        value['default_icon'],
        warnings,
        'sidebar_action.default_icon',
      ),
      openAtInstall: reader.boolean('open_at_install') ?? true,
    );
  }

  static List<WebAccessibleResource> _parseWebAccessible(
    Object? value,
    int manifestVersion,
    List<String> warnings,
  ) {
    if (value is! List) return const [];

    final result = <WebAccessibleResource>[];
    for (final item in value) {
      if (item is String) {
        // MV2: a bare list of paths, visible to every page.
        result.add(
          WebAccessibleResource(
            resources: [item],
            matches: const ['<all_urls>'],
          ),
        );
      } else if (item is Map) {
        final reader = _Reader(
          item.cast<String, Object?>(),
          'web_accessible_resources.',
          warnings,
        );
        result.add(
          WebAccessibleResource(
            resources: reader.strings('resources'),
            matches: reader.strings('matches'),
            extensionIds: reader.strings('extension_ids'),
          ),
        );
      }
    }
    return result;
  }

  static List<CommandSpec> _parseCommands(
    Object? value,
    List<String> warnings,
  ) {
    if (value is! Map) return const [];

    final commands = <CommandSpec>[];
    for (final entry in value.entries) {
      final item = entry.value;
      if (item is! Map) continue;
      final reader = _Reader(
        item.cast<String, Object?>(),
        'commands.${entry.key}.',
        warnings,
      );
      commands.add(
        CommandSpec(
          name: entry.key.toString(),
          description: reader.string('description'),
          suggestedKey: _parseStringMap(item['suggested_key']),
        ),
      );
    }
    return commands;
  }

  static ContentSecurityPolicy _parseCsp(Object? value, int manifestVersion) {
    final fallback = manifestVersion == 3
        ? ContentSecurityPolicy.defaultMv3
        : ContentSecurityPolicy.defaultMv2;

    if (value is String && manifestVersion == 2) {
      return ContentSecurityPolicy(extensionPages: value);
    }
    if (value is Map) {
      final pages = value['extension_pages'];
      final sandbox = value['sandbox'];
      return ContentSecurityPolicy(
        extensionPages: pages is String ? pages : fallback,
        sandbox: sandbox is String ? sandbox : null,
      );
    }
    return ContentSecurityPolicy(extensionPages: fallback);
  }

  static List<DnrRuleResource> _parseDnr(Object? value, List<String> warnings) {
    if (value is! Map) return const [];
    final resources = value['rule_resources'];
    if (resources is! List) return const [];

    final parsed = <DnrRuleResource>[];
    for (final item in resources) {
      if (item is! Map) continue;
      final id = item['id'];
      final path = item['path'];
      if (id is! String || path is! String) continue;
      final normalized = normalizeResourcePath(path);
      if (normalized == null) {
        warnings.add('declarative_net_request: ignoring unsafe path "$path"');
        continue;
      }
      parsed.add(
        DnrRuleResource(
          id: id,
          path: normalized,
          enabled: item['enabled'] == true,
        ),
      );
    }
    return parsed;
  }

  static String? _parseOmnibox(Object? value) {
    if (value is! Map) return null;
    final keyword = value['keyword'];
    return keyword is String && keyword.isNotEmpty ? keyword : null;
  }

  static Map<String, String> _parseStringMap(Object? value) {
    if (value is String) return {'default': value};
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is String) entry.key.toString(): entry.value as String,
    };
  }
}

/// Typed access to the keys of one JSON object, noting what could not be
/// used instead of failing.
class _Reader {
  _Reader(this._json, this._prefix, this._warnings);

  final Map<String, Object?> _json;
  final String _prefix;
  final List<String> _warnings;

  String? string(String key) {
    final value = _json[key];
    if (value == null) return null;
    if (value is String) return value;
    _warnings.add('$_prefix$key must be a string');
    return null;
  }

  bool? boolean(String key) {
    final value = _json[key];
    if (value == null) return null;
    if (value is bool) return value;
    _warnings.add('$_prefix$key must be a boolean');
    return null;
  }

  List<String> strings(String key) {
    final value = _json[key];
    if (value == null) return const [];
    if (value is! List) {
      _warnings.add('$_prefix$key must be an array');
      return const [];
    }

    final result = <String>[];
    for (final item in value) {
      if (item is String) {
        result.add(item);
      } else {
        _warnings.add('$_prefix$key has a non-string entry');
      }
    }
    return result;
  }
}
