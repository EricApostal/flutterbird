// A command-line front end to the installer, for trying it without the app:
//
//   dart run bird_extensions:bird_ext info ublock-origin
//   dart run bird_extensions:bird_ext install ublock-origin --root /tmp/ext
//   dart run bird_extensions:bird_ext list --root /tmp/ext
//
// `info` only reads AMO's listing. `install` and `update` download the add-on
// (from addons.mozilla.org only) after showing what it asks for.
import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';

const String _usage = '''
Usage: bird_ext <command> [arguments] [--root DIR] [--yes]

Commands:
  info <slug|url|guid>       Show what AMO lists for an add-on (no download).
  install <slug|url|guid>    Download, show permissions, and install.
  load <directory>           Install an unpacked extension folder (development).
  update [id]                Update one extension, or all AMO ones.
  list                       List installed extensions.
  uninstall <id>             Remove an extension.

Options:
  --root DIR   Where extensions live (default: \$BIRD_EXTENSIONS_DIR or
               ~/.flutterbird-extensions-dev).
  --yes        Do not ask before installing or updating.
''';

Future<void> main(List<String> arguments) async {
  // Returning from main does not set the exit code in Dart.
  exitCode = await _run(arguments);
}

Future<int> _run(List<String> arguments) async {
  final positional = <String>[];
  String? rootOption;
  var assumeYes = false;

  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--yes' || argument == '-y') {
      assumeYes = true;
    } else if (argument == '--root' && i + 1 < arguments.length) {
      rootOption = arguments[++i];
    } else if (argument == '--help' || argument == '-h') {
      stdout.write(_usage);
      return 0;
    } else {
      positional.add(argument);
    }
  }

  if (positional.isEmpty) {
    stderr.write(_usage);
    return 64;
  }

  final root = Directory(
    rootOption ??
        Platform.environment['BIRD_EXTENSIONS_DIR'] ??
        '${Platform.environment['HOME'] ?? '.'}/.flutterbird-extensions-dev',
  );

  final fetcher = IoHttpFetcher(userAgent: 'FlutterBird-extensions-cli');
  final amo = AmoClient(fetcher);

  try {
    switch (positional.first) {
      case 'info':
        return await _info(amo, positional.skip(1));
      case 'install':
        return await _install(root, amo, positional.skip(1), assumeYes);
      case 'load':
        return await _load(root, amo, positional.skip(1), assumeYes);
      case 'update':
        return await _update(root, amo, positional.skip(1), assumeYes);
      case 'list':
        return await _list(root);
      case 'uninstall':
        return await _uninstall(root, amo, positional.skip(1));
      default:
        stderr.write(_usage);
        return 64;
    }
  } on InstallCancelled {
    stdout.writeln('Cancelled.');
    return 1;
  } on AmoInputException catch (error) {
    stderr.writeln(error.message);
    return 64;
  } on AmoException catch (error) {
    stderr.writeln(error.message);
    return 1;
  } on InstallException catch (error) {
    stderr.writeln(error.message);
    return 1;
  } on FetchException catch (error) {
    stderr.writeln(error.message);
    return 1;
  } finally {
    fetcher.close();
  }
}

Future<int> _info(AmoClient amo, Iterable<String> inputs) async {
  if (inputs.isEmpty) {
    stderr.write(_usage);
    return 64;
  }

  final addon = await amo.lookup(inputs.first);
  stdout
    ..writeln('${addon.name} ${addon.version}')
    ..writeln('  guid:        ${addon.guid}')
    ..writeln('  slug:        ${addon.slug}')
    ..writeln('  type:        ${addon.type}')
    ..writeln('  size:        ${addon.fileSize ?? 'unknown'} bytes')
    ..writeln('  file:        ${addon.fileUrl}')
    ..writeln('  hash:        ${addon.fileHash ?? 'none published'}')
    ..writeln('  permissions: ${addon.permissions.join(', ')}');
  return 0;
}

Future<int> _install(
  Directory root,
  AmoClient amo,
  Iterable<String> inputs,
  bool assumeYes,
) async {
  if (inputs.isEmpty) {
    stderr.write(_usage);
    return 64;
  }

  final registry = await ExtensionRegistry.open(root);
  final installer = ExtensionInstaller(registry: registry, amo: amo);

  final result = await installer.installFromAmo(
    inputs.first,
    onPrompt: (prompt) => _confirm(prompt, assumeYes),
    onProgress: _progress,
  );
  stderr.writeln();

  _printResult(registry, result);
  await registry.dispose();
  return 0;
}

Future<int> _load(
  Directory root,
  AmoClient amo,
  Iterable<String> inputs,
  bool assumeYes,
) async {
  if (inputs.isEmpty) {
    stderr.write(_usage);
    return 64;
  }

  final registry = await ExtensionRegistry.open(root);
  final installer = ExtensionInstaller(registry: registry, amo: amo);

  final result = await installer.installFromDirectory(
    Directory(inputs.first),
    onPrompt: (prompt) => _confirm(prompt, assumeYes),
  );

  _printResult(registry, result);
  await registry.dispose();
  return 0;
}

Future<int> _update(
  Directory root,
  AmoClient amo,
  Iterable<String> inputs,
  bool assumeYes,
) async {
  final registry = await ExtensionRegistry.open(root);
  final installer = ExtensionInstaller(registry: registry, amo: amo);

  final ids = inputs.isNotEmpty
      ? [inputs.first]
      : [
          for (final extension in registry.extensions)
            if (extension.source.isAmo) extension.id,
        ];

  var updated = 0;
  for (final id in ids) {
    final result = await installer.update(
      id,
      onPrompt: (prompt) => _confirm(prompt, assumeYes),
      onProgress: _progress,
    );
    if (result == null) {
      stdout.writeln('$id is up to date');
    } else {
      stderr.writeln();
      _printResult(registry, result);
      updated++;
    }
  }

  stdout.writeln('$updated updated.');
  await registry.dispose();
  return 0;
}

Future<int> _list(Directory root) async {
  final registry = await ExtensionRegistry.open(root);
  if (registry.extensions.isEmpty) {
    stdout.writeln('Nothing installed in ${root.path}');
  }
  for (final extension in registry.extensions) {
    stdout.writeln(
      '${extension.enabled ? ' ' : 'x'} ${extension.name} ${extension.version}'
      '  ${extension.id}  ${extension.origin}  MV${extension.manifestVersion}',
    );
  }
  await registry.dispose();
  return 0;
}

Future<int> _uninstall(
  Directory root,
  AmoClient amo,
  Iterable<String> inputs,
) async {
  if (inputs.isEmpty) {
    stderr.write(_usage);
    return 64;
  }

  final registry = await ExtensionRegistry.open(root);
  final installer = ExtensionInstaller(registry: registry, amo: amo);

  if (registry.byId(inputs.first) == null) {
    stderr.writeln('${inputs.first} is not installed');
    await registry.dispose();
    return 1;
  }

  await installer.uninstall(inputs.first);
  stdout.writeln('Removed ${inputs.first}');
  await registry.dispose();
  return 0;
}

Future<bool> _confirm(InstallPrompt prompt, bool assumeYes) async {
  stderr.writeln();
  stdout
    ..writeln(
      '${prompt.isUpdate ? 'Update' : 'Add'} ${prompt.name} ${prompt.version}?',
    )
    ..writeln('  id: ${prompt.id}');

  if (prompt.permissions.isEmpty) {
    stdout.writeln('  It asks for no special permissions.');
  } else {
    stdout.writeln(prompt.isUpdate ? '  New permissions:' : '  It asks to:');
    for (final line in prompt.permissions.lines) {
      stdout.writeln('    - $line');
    }
  }
  for (final line in prompt.permissions.dataCollectionLines) {
    stdout.writeln('  $line');
  }
  for (final warning in prompt.warnings) {
    stdout.writeln('  note: $warning');
  }

  if (assumeYes) return true;

  stdout.write('Continue? [y/N] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase();
  return answer == 'y' || answer == 'yes';
}

void _printResult(ExtensionRegistry registry, InstallResult result) {
  final extension = result.extension;
  stdout
    ..writeln(
      '${result.wasUpdate ? 'Updated' : 'Installed'} ${extension.name} '
      '${extension.version}',
    )
    ..writeln('  id:     ${extension.id}')
    ..writeln('  origin: ${extension.origin}')
    ..writeln('  files:  ${registry.directoryFor(extension).path}');
  for (final warning in result.warnings) {
    stdout.writeln('  note: $warning');
  }
}

void _progress(int received, int? total) {
  final percent = total == null || total == 0
      ? ''
      : ' (${(received * 100 ~/ total)}%)';
  stderr.write('\rDownloading… $received bytes$percent   ');
}
