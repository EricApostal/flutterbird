import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'manifest.dart';

/// Where an installed extension came from, which decides how it is updated.
class InstallSource {
  const InstallSource.amo({required this.slug, required this.amoId})
    : kind = 'amo';

  const InstallSource.file() : kind = 'file', slug = null, amoId = null;

  const InstallSource._(this.kind, this.slug, this.amoId);

  factory InstallSource.fromJson(Object? json) {
    if (json is Map && json['kind'] == 'amo') {
      final id = json['amoId'];
      final slug = json['slug'];
      if (slug is String && id is int) {
        return InstallSource._('amo', slug, id);
      }
    }
    return const InstallSource.file();
  }

  /// `amo` or `file`.
  final String kind;
  final String? slug;
  final int? amoId;

  bool get isAmo => kind == 'amo';

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (slug != null) 'slug': slug,
    if (amoId != null) 'amoId': amoId,
  };
}

/// One installed extension, as the registry stores it.
class InstalledExtension {
  const InstalledExtension({
    required this.id,
    required this.uuid,
    required this.version,
    required this.name,
    required this.manifestVersion,
    required this.type,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
    required this.source,
    this.description,
    this.iconPath,
    this.grantedPermissions = const [],
    this.grantedOrigins = const [],
    this.privateBrowsingAllowed = false,
  });

  factory InstalledExtension.fromJson(Map<String, Object?> json) {
    List<String> strings(Object? value) => value is List
        ? [
            for (final item in value)
              if (item is String) item,
          ]
        : const [];

    return InstalledExtension(
      id: json['id']! as String,
      uuid: json['uuid']! as String,
      version: json['version']! as String,
      name: json['name']! as String,
      description: json['description'] as String?,
      iconPath: json['iconPath'] as String?,
      manifestVersion: json['manifestVersion'] as int? ?? 2,
      type: ExtensionType.values.firstWhere(
        (candidate) => candidate.name == json['type'],
        orElse: () => ExtensionType.extension,
      ),
      enabled: json['enabled'] as bool? ?? true,
      installedAt: DateTime.parse(json['installedAt']! as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt']! as String).toUtc(),
      source: InstallSource.fromJson(json['source']),
      grantedPermissions: strings(json['grantedPermissions']),
      grantedOrigins: strings(json['grantedOrigins']),
      privateBrowsingAllowed: json['privateBrowsingAllowed'] as bool? ?? false,
    );
  }

  /// The id the extension declares, such as `uBlock0@raymondhill.net`.
  final String id;

  /// A random identifier minted at install. It names the extension's
  /// directory and its `moz-extension://<uuid>/` origin, and is not derived
  /// from [id] so that a page cannot probe which extensions are installed.
  final String uuid;

  final String version;

  /// The name after localization.
  final String name;
  final String? description;

  /// Relative path of the icon to show for this extension, if it has one.
  final String? iconPath;
  final int manifestVersion;
  final ExtensionType type;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;
  final InstallSource source;

  /// API permissions the user has granted.
  final List<String> grantedPermissions;

  /// Host patterns the user has granted.
  final List<String> grantedOrigins;
  final bool privateBrowsingAllowed;

  /// The extension's own origin, which its pages and resources live under.
  String get origin => 'moz-extension://$uuid';

  InstalledExtension copyWith({
    String? version,
    String? name,
    String? description,
    String? iconPath,
    int? manifestVersion,
    ExtensionType? type,
    bool? enabled,
    DateTime? updatedAt,
    InstallSource? source,
    List<String>? grantedPermissions,
    List<String>? grantedOrigins,
    bool? privateBrowsingAllowed,
  }) {
    return InstalledExtension(
      id: id,
      uuid: uuid,
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      iconPath: iconPath ?? this.iconPath,
      manifestVersion: manifestVersion ?? this.manifestVersion,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      grantedPermissions: grantedPermissions ?? this.grantedPermissions,
      grantedOrigins: grantedOrigins ?? this.grantedOrigins,
      privateBrowsingAllowed:
          privateBrowsingAllowed ?? this.privateBrowsingAllowed,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'uuid': uuid,
    'version': version,
    'name': name,
    if (description != null) 'description': description,
    if (iconPath != null) 'iconPath': iconPath,
    'manifestVersion': manifestVersion,
    'type': type.name,
    'enabled': enabled,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'source': source.toJson(),
    'grantedPermissions': grantedPermissions,
    'grantedOrigins': grantedOrigins,
    'privateBrowsingAllowed': privateBrowsingAllowed,
  };
}

enum RegistryChangeKind { added, updated, removed }

class RegistryChange {
  const RegistryChange(this.kind, this.extension);

  final RegistryChangeKind kind;
  final InstalledExtension extension;
}

/// The set of installed extensions and where their files are.
///
/// Layout under [root]:
///
///     registry.json          what is installed and granted
///     installed/<uuid>/      the unpacked extension
///     storage/<uuid>.json    browser.storage.local contents (later)
///
/// Extensions live in directories named by random uuid, never by anything
/// the extension declares, so a hostile id cannot name a path.
class ExtensionRegistry {
  ExtensionRegistry._(this.root, this._extensions);

  static const int _version = 1;

  final Directory root;
  final Map<String, InstalledExtension> _extensions;
  final StreamController<RegistryChange> _changes =
      StreamController<RegistryChange>.broadcast();
  Future<void> _writeQueue = Future<void>.value();

  /// Opens the registry in [root], creating the directory if needed.
  ///
  /// A registry file that cannot be read is set aside rather than deleted
  /// and the registry starts empty, so one corrupt write cannot leave the
  /// browser unable to start. The extension directories are left alone.
  static Future<ExtensionRegistry> open(Directory root) async {
    await root.create(recursive: true);
    final file = File('${root.path}/registry.json');
    final extensions = <String, InstalledExtension>{};

    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        final list = decoded is Map ? decoded['extensions'] : null;
        if (list is! List) throw const FormatException('no extensions list');

        for (final item in list) {
          final extension = InstalledExtension.fromJson(
            (item as Map).cast<String, Object?>(),
          );
          extensions[extension.id] = extension;
        }
      } on Object {
        extensions.clear();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        await file.rename('${root.path}/registry.json.corrupt-$stamp');
      }
    }

    return ExtensionRegistry._(root, extensions);
  }

  List<InstalledExtension> get extensions =>
      _extensions.values.toList(growable: false);

  Stream<RegistryChange> get changes => _changes.stream;

  InstalledExtension? byId(String id) => _extensions[id];

  InstalledExtension? byUuid(String uuid) {
    for (final extension in _extensions.values) {
      if (extension.uuid == uuid) return extension;
    }
    return null;
  }

  /// The directory an extension's files are unpacked into.
  Directory directoryFor(InstalledExtension extension) =>
      Directory('${root.path}/installed/${extension.uuid}');

  /// A scratch directory next to the installed ones, so that the final move
  /// is a rename on the same filesystem.
  Directory stagingDirectory() =>
      Directory('${root.path}/installed/.staging-${_randomHex(8)}');

  /// Adds [extension], or replaces the one with the same id.
  Future<void> put(InstalledExtension extension) async {
    final existed = _extensions.containsKey(extension.id);
    _extensions[extension.id] = extension;
    await _save();
    _changes.add(
      RegistryChange(
        existed ? RegistryChangeKind.updated : RegistryChangeKind.added,
        extension,
      ),
    );
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    final current = _extensions[id];
    if (current == null || current.enabled == enabled) return;
    await put(current.copyWith(enabled: enabled));
  }

  /// Forgets [id]. The caller removes the files.
  Future<InstalledExtension?> remove(String id) async {
    final removed = _extensions.remove(id);
    if (removed == null) return null;
    await _save();
    _changes.add(RegistryChange(RegistryChangeKind.removed, removed));
    return removed;
  }

  /// A fresh identifier for a new install.
  static String newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // RFC 4122 version 4.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List<String>.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Writes the registry, one write at a time and by renaming a finished
  /// temporary file into place so a crash never leaves half a file.
  Future<void> _save() {
    final next = _writeQueue.then((_) async {
      final document = jsonEncode({
        'version': _version,
        'extensions': [for (final item in _extensions.values) item.toJson()],
      });

      final temporary = File('${root.path}/registry.json.tmp');
      await temporary.writeAsString(document, flush: true);
      await temporary.rename('${root.path}/registry.json');
    });

    // Keep the queue alive after a failed write so later saves still run.
    _writeQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> dispose() async {
    await _writeQueue;
    await _changes.close();
  }
}
