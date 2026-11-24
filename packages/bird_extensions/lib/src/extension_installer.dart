import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'amo_client.dart';
import 'extension_registry.dart';
import 'localization.dart';
import 'manifest.dart';
import 'permissions.dart';
import 'version.dart';
import 'xpi_extractor.dart';
import 'zip_reader.dart';
import 'zip_writer.dart';

/// The package could not be installed.
class InstallException implements Exception {
  InstallException(this.message);

  final String message;

  @override
  String toString() => 'InstallException: $message';
}

/// The user declined the install or update prompt.
class InstallCancelled implements Exception {
  @override
  String toString() => 'InstallCancelled';
}

/// What the user is asked to approve.
class InstallPrompt {
  const InstallPrompt({
    required this.id,
    required this.name,
    required this.version,
    required this.permissions,
    required this.isUpdate,
    this.description,
    this.warnings = const [],
  });

  final String id;
  final String name;
  final String version;
  final String? description;

  /// For an update, only what the new version adds.
  final PermissionPrompt permissions;
  final bool isUpdate;
  final List<String> warnings;
}

/// Asks the user to approve [prompt]. Returns true to go ahead.
typedef InstallPromptHandler = Future<bool> Function(InstallPrompt prompt);

class InstallResult {
  const InstallResult({
    required this.extension,
    required this.warnings,
    required this.wasUpdate,
  });

  final InstalledExtension extension;

  /// Things in the manifest that were ignored or point at missing files.
  final List<String> warnings;
  final bool wasUpdate;
}

/// Installs, updates and removes extensions.
class ExtensionInstaller {
  ExtensionInstaller({
    required this.registry,
    required this.amo,
    this.preferredLocales = const ['en-US', 'en'],
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ExtensionRegistry registry;
  final AmoClient amo;

  /// The user's locales, most preferred first, for choosing which
  /// translation of an extension's name to store.
  final List<String> preferredLocales;
  final DateTime Function() _clock;

  static const int _maxManifestBytes = 4 * 1024 * 1024;

  /// Installs the add-on named by [input]: an AMO page URL, a slug, a GUID
  /// or a numeric id.
  ///
  /// When [onPrompt] is null the install is approved without asking, which
  /// is for tests and tooling; a user-facing caller always passes one.
  Future<InstallResult> installFromAmo(
    String input, {
    InstallPromptHandler? onPrompt,
    void Function(int received, int? total)? onProgress,
  }) async {
    final addon = await amo.lookup(input);
    return _installAddon(addon, onPrompt: onPrompt, onProgress: onProgress);
  }

  /// Installs a package already in memory, such as a file the user picked.
  Future<InstallResult> installFromBytes(
    Uint8List bytes, {
    InstallPromptHandler? onPrompt,
  }) {
    return _install(
      bytes,
      source: const InstallSource.file(),
      expectedId: null,
      onPrompt: onPrompt,
    );
  }

  /// Installs an unpacked extension folder, the way Firefox's "Load Temporary
  /// Add-on" does, for developing an extension.
  Future<InstallResult> installFromDirectory(
    Directory directory, {
    InstallPromptHandler? onPrompt,
  }) async {
    if (!await File('${directory.path}/manifest.json').exists()) {
      throw InstallException('${directory.path} has no manifest.json');
    }
    return installFromBytes(await zipDirectory(directory), onPrompt: onPrompt);
  }

  Future<InstallResult> _installAddon(
    AmoAddon addon, {
    InstallPromptHandler? onPrompt,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (addon.type != 'extension') {
      throw InstallException(
        '${addon.name} is a ${addon.type}; only extensions can be installed',
      );
    }
    if (addon.requiresPayment) {
      throw InstallException(
        '${addon.name} requires payment and cannot be installed',
      );
    }

    final bytes = await amo.download(addon, onProgress: onProgress);
    return _install(
      bytes,
      source: InstallSource.amo(slug: addon.slug, amoId: addon.id),
      expectedId: addon.guid,
      onPrompt: onPrompt,
    );
  }

  /// The newer AMO version of [extension], or null if it is up to date or
  /// did not come from AMO.
  Future<AmoAddon?> checkForUpdate(InstalledExtension extension) async {
    if (!extension.source.isAmo) return null;

    final addon = await amo.lookup(extension.id);
    return compareVersions(addon.version, extension.version) > 0 ? addon : null;
  }

  /// Updates [id] if AMO has a newer version. Returns null when it did not
  /// need updating. The extension keeps its uuid, so its origin and its
  /// stored data carry over.
  Future<InstallResult?> update(
    String id, {
    InstallPromptHandler? onPrompt,
    void Function(int received, int? total)? onProgress,
  }) async {
    final extension = registry.byId(id);
    if (extension == null) throw InstallException('$id is not installed');

    final addon = await checkForUpdate(extension);
    if (addon == null) return null;
    return _installAddon(addon, onPrompt: onPrompt, onProgress: onProgress);
  }

  Future<void> uninstall(String id) async {
    final extension = await registry.remove(id);
    if (extension == null) return;

    final directory = registry.directoryFor(extension);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<InstallResult> _install(
    Uint8List bytes, {
    required InstallSource source,
    required String? expectedId,
    required InstallPromptHandler? onPrompt,
  }) async {
    final ZipArchive archive;
    try {
      archive = ZipArchive.fromBytes(bytes);
    } on ZipFormatException catch (error) {
      throw InstallException(
        'This is not a valid add-on package: ${error.message}',
      );
    }

    final manifestEntry = archive.find('manifest.json');
    if (manifestEntry == null) {
      throw InstallException('The package has no manifest.json');
    }

    final ManifestParseResult parsed;
    try {
      parsed = Manifest.parseBytes(
        archive.read(manifestEntry, maxBytes: _maxManifestBytes),
      );
    } on ManifestException catch (error) {
      throw InstallException(error.message);
    } on ZipFormatException catch (error) {
      throw InstallException('Could not read manifest.json: ${error.message}');
    }
    final manifest = parsed.manifest;
    final warnings = [...parsed.warnings];

    if (manifest.type != ExtensionType.extension) {
      throw InstallException(
        'This package is a ${manifest.type.name}; only extensions can be installed',
      );
    }

    final declaredId = manifest.id;
    if (declaredId != null && expectedId != null && declaredId != expectedId) {
      throw InstallException(
        'The package says it is $declaredId but AMO listed it as $expectedId',
      );
    }

    final previous = declaredId != null || expectedId != null
        ? registry.byId((declaredId ?? expectedId)!)
        : null;
    final uuid = previous?.uuid ?? ExtensionRegistry.newUuid();
    final id = declaredId ?? expectedId ?? '$uuid@local.flutterbird';

    // The stored name is the translated one, so listings read naturally
    // without opening the package again.
    final locale = chooseLocale(
      available: availableLocales(archive),
      preferred: preferredLocales,
      defaultLocale: manifest.defaultLocale,
    );
    final catalog = readCatalog(archive, locale);
    var name = catalog.localize(manifest.name).trim();
    if (name.isEmpty || name.contains('__MSG_')) name = id;
    final description = manifest.description == null
        ? null
        : catalog.localize(manifest.description!).trim();

    // Hosts the extension asks for. MV2 also asks for every page its
    // content scripts run on.
    final requestedOrigins = {
      ...manifest.hostPermissions,
      if (!manifest.isManifestV3) ...manifest.contentScriptMatches,
    }.toList();
    final requestedPermissions = manifest.permissions;

    final alreadyGranted = {
      ...?previous?.grantedPermissions,
      ...?previous?.grantedOrigins,
    };
    final newPermissions = addedPermissions(
      granted: alreadyGranted,
      next: requestedPermissions,
    );
    final newOrigins = addedPermissions(
      granted: alreadyGranted,
      next: requestedOrigins,
    );

    final isUpdate = previous != null;
    final promptPermissions = describePermissions(
      permissions: isUpdate ? newPermissions : requestedPermissions,
      hostPatterns: isUpdate ? newOrigins : requestedOrigins,
      requiredDataCollection: isUpdate
          ? const []
          : manifest.gecko?.requiredDataCollection ?? const [],
    );

    // An update that asks for nothing new installs without interrupting.
    final needsPrompt = !isUpdate || !promptPermissions.isEmpty;
    if (needsPrompt && onPrompt != null) {
      final approved = await onPrompt(
        InstallPrompt(
          id: id,
          name: name,
          version: manifest.version,
          description: description,
          permissions: promptPermissions,
          isUpdate: isUpdate,
          warnings: warnings,
        ),
      );
      if (!approved) throw InstallCancelled();
    }

    final staging = registry.stagingDirectory();
    await staging.create(recursive: true);

    final InstalledExtension extension;
    try {
      try {
        await extractArchive(archive, staging);
      } on ZipFormatException catch (error) {
        throw InstallException(
          'Could not unpack the package: ${error.message}',
        );
      }

      warnings.addAll(await _missingFileWarnings(manifest, staging));
      await _writeGeneratedBackgroundPage(manifest, staging);

      final now = _clock().toUtc();
      final optionalGrants = {
        ...manifest.optionalPermissions,
        ...manifest.optionalHostPermissions,
      };
      final keptOptional = [
        ...?previous?.grantedPermissions,
        ...?previous?.grantedOrigins,
      ].where(optionalGrants.contains);

      extension = InstalledExtension(
        id: id,
        uuid: uuid,
        version: manifest.version,
        name: name,
        description: description,
        iconPath: _pickIcon(manifest),
        manifestVersion: manifest.manifestVersion,
        type: manifest.type,
        enabled: previous?.enabled ?? true,
        installedAt: previous?.installedAt ?? now,
        updatedAt: now,
        source: source,
        grantedPermissions: {
          ...requestedPermissions,
          ...keptOptional.where((grant) => !_isOrigin(grant)),
        }.toList(),
        grantedOrigins: {
          ...requestedOrigins,
          ...keptOptional.where(_isOrigin),
        }.toList(),
        privateBrowsingAllowed: previous?.privateBrowsingAllowed ?? false,
      );

      await _swapIn(extension, staging);
    } on Object {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }

    return InstallResult(
      extension: extension,
      warnings: warnings,
      wasUpdate: isUpdate,
    );
  }

  /// Moves [staging] into the extension's directory and records it, undoing
  /// the move if recording fails.
  Future<void> _swapIn(InstalledExtension extension, Directory staging) async {
    final target = registry.directoryFor(extension);
    Directory? displaced;

    if (await target.exists()) {
      displaced = Directory(
        '${target.path}.old-${ExtensionRegistry.newUuid()}',
      );
      await target.rename(displaced.path);
    }

    try {
      await staging.rename(target.path);
      await registry.put(extension);
    } on Object {
      if (await target.exists()) await target.delete(recursive: true);
      if (displaced != null) await displaced.rename(target.path);
      rethrow;
    }

    if (displaced != null) {
      try {
        await displaced.delete(recursive: true);
      } on FileSystemException {
        // The new version is live; a leftover directory is only clutter.
      }
    }
  }

  /// Firefox gives an extension whose background is a list of scripts a page
  /// that loads them. This writes that page, so that the background has a URL
  /// like any other page.
  Future<void> _writeGeneratedBackgroundPage(
    Manifest manifest,
    Directory root,
  ) async {
    final background = manifest.background;
    if (background == null ||
        background.page != null ||
        background.scripts.isEmpty) {
      return;
    }

    final buffer = StringBuffer(
      '<!DOCTYPE html>\n<html>\n<head><meta charset="utf-8"></head>\n<body>\n',
    );
    for (final script in background.scripts) {
      final type = background.isModule ? ' type="module"' : '';
      buffer.writeln(
        '<script$type src="${const HtmlEscape(HtmlEscapeMode.attribute).convert(script)}"></script>',
      );
    }
    buffer.writeln('</body>\n</html>');

    await File(
      '${root.path}/_generated_background_page.html',
    ).writeAsString(buffer.toString());
  }

  static bool _isOrigin(String grant) =>
      grant == '<all_urls>' || grant.contains('://');

  String? _pickIcon(Manifest manifest) {
    return bestIconPath(manifest.icons, 48) ??
        (manifest.action == null
            ? null
            : bestIconPath(manifest.action!.defaultIcon, 48));
  }

  Future<List<String>> _missingFileWarnings(
    Manifest manifest,
    Directory root,
  ) async {
    final referenced = <String>{
      for (final script in manifest.contentScripts) ...script.js,
      for (final script in manifest.contentScripts) ...script.css,
      ...?manifest.background?.scripts,
      if (manifest.background?.page != null) manifest.background!.page!,
      if (manifest.action?.defaultPopup != null) manifest.action!.defaultPopup!,
      if (manifest.options != null) manifest.options!.page,
    };

    final warnings = <String>[];
    for (final path in referenced) {
      if (!await File('${root.path}/$path').exists()) {
        warnings.add(
          'The manifest refers to "$path", which is not in the package',
        );
      }
    }
    return warnings;
  }
}
