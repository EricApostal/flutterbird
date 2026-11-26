import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bird_extensions/bird_extensions.dart';

/// Where the pieces of a disposable browser are put together.
///
/// The engine looks for its helper programs beside the program hosting it and
/// for its resources in `../Resources`, so engine_host.c is compiled into a
/// copy of the app's layout. The copies are clones, which cost nothing on APFS.
/// Nothing of the engine or the app is built.
class Stage {
  Stage(this.root);

  final Directory root;

  String get hostBinary => '${root.path}/Stage.app/Contents/MacOS/engine_host';
  String get engineLibrary =>
      '${root.path}/Stage.app/Contents/Resources/libengine.dylib';

  static Future<Stage> prepare(
    Directory app,
    Directory root, {
    Directory? engineBuild,
  }) async {
    final contents = '${app.path}/Contents';
    if (!await File('$contents/Resources/libengine.dylib').exists()) {
      throw StateError(
        'There is no built app at ${app.path}. Build it first, or pass --app.',
      );
    }
    final macos = Directory('${root.path}/Stage.app/Contents/MacOS');
    await macos.create(recursive: true);
    await _run('cp', [
      '-Rc',
      '$contents/Resources',
      '${root.path}/Stage.app/Contents/Resources',
    ]);
    await for (final helper in Directory('$contents/MacOS').list()) {
      final name = helper.uri.pathSegments.last;
      // The app itself is not wanted, only what the engine starts.
      if (helper is File && !name.contains(' ')) {
        await _run('cp', ['-c', helper.path, '${macos.path}/$name']);
      }
    }
    if (engineBuild != null) await _overlay(engineBuild, root);
    final stage = Stage(root);
    final source = Platform.script.resolve('engine_host.c').toFilePath();
    await _run('clang', ['-Wall', '-O1', source, '-o', stage.hostBinary]);
    return stage;
  }

  /// Puts the libraries and helper programs of a Ladybird build in place of
  /// the app's, so that an engine change can be tried without building the app.
  static Future<void> _overlay(Directory build, Directory root) async {
    final contents = '${root.path}/Stage.app/Contents';
    final libraries = '$contents/Resources/ladybird_libs';
    await for (final entry in Directory('${build.path}/lib').list()) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final installed = '$libraries/$name';
      // Only what the app already carries, each real file once: the other
      // names are links to it.
      if (entry is File &&
          name.startsWith('liblagom-') &&
          await FileSystemEntity.type(installed, followLinks: false) ==
              FileSystemEntityType.file) {
        await _run('cp', ['-f', entry.path, installed]);
      }
    }
    final helpers = '${build.path}/bin/Ladybird.app/Contents/MacOS';
    await for (final helper in Directory('$contents/MacOS').list()) {
      final name = helper.uri.pathSegments.last;
      if (!await File('$helpers/$name').exists()) continue;
      await _run('cp', ['-f', '$helpers/$name', helper.path]);
      // As the app's build does: libraries are found in the bundle first.
      final loaded = await Process.run('otool', ['-l', helper.path]);
      for (final match in RegExp(
        r'cmd LC_RPATH\s+cmdsize \d+\s+path (\S+)',
      ).allMatches('${loaded.stdout}')) {
        await _run('install_name_tool', [
          '-delete_rpath',
          match[1]!,
          helper.path,
        ]);
      }
      await _run('install_name_tool', [
        '-add_rpath',
        '@executable_path/../Resources/ladybird_libs',
        helper.path,
      ]);
      await _run('codesign', ['--force', '--sign', '-', helper.path]);
    }
  }

  static Future<void> _run(String program, List<String> arguments) async {
    final result = await Process.run(program, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(program, arguments, '${result.stderr}');
    }
  }
}

typedef ViewEvent = ({int view, String? url, bool? loading});
typedef Intercept = ({int request, int view, String details});

/// The engine, running in engine_host.
class Engine implements ExtensionTransport {
  Engine._(this._process, this._log);

  final Process _process;
  final IOSink _log;
  final _created = StreamController<ExtensionContext>.broadcast();
  final _destroyed = StreamController<int>.broadcast();
  final _messages = StreamController<TransportMessage>.broadcast();
  final _viewEvents = StreamController<ViewEvent>.broadcast();
  final _intercepts = StreamController<Intercept>.broadcast();
  final _ready = Completer<void>();
  final Map<int, Completer<int>> _creating = {};
  var _nextRequest = 1;
  var _buffer = Uint8List(0);
  var _stopping = false;

  /// Completes with the exit code if the engine goes away on its own.
  final crashed = Completer<int>();

  @override
  Stream<ExtensionContext> get contextCreated => _created.stream;
  @override
  Stream<int> get contextDestroyed => _destroyed.stream;
  @override
  Stream<TransportMessage> get messages => _messages.stream;
  Stream<ViewEvent> get viewEvents => _viewEvents.stream;
  Stream<Intercept> get intercepts => _intercepts.stream;

  /// Starts an engine whose profile is under [home], which keeps it away from
  /// the profile of whoever runs this.
  static Future<Engine> start(Stage stage, Directory home, File log) async {
    await home.create(recursive: true);
    final process = await Process.start(
      stage.hostBinary,
      [stage.engineLibrary],
      environment: {
        'HOME': home.path,
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'TMPDIR': Platform.environment['TMPDIR'] ?? '/tmp',
      },
      includeParentEnvironment: false,
    );
    final engine = Engine._(process, log.openWrite(mode: FileMode.append));
    process.stdout.listen(engine._receive);
    process.stderr.listen(engine._log.add);
    unawaited(
      process.exitCode.then((code) {
        if (!engine._stopping) engine.crashed.complete(code);
        if (!engine._ready.isCompleted) {
          engine._ready.completeError(StateError('The engine exited: $code'));
        }
      }),
    );
    await engine._ready.future.timeout(const Duration(seconds: 60));
    return engine;
  }

  void _receive(List<int> chunk) {
    _buffer = Uint8List.fromList([..._buffer, ...chunk]);
    var offset = 0;
    while (true) {
      final newline = _buffer.indexOf(10, offset);
      if (newline < 0) break;
      final header = ascii.decode(_buffer.sublist(offset, newline)).split(' ');
      final length = int.parse(header[4]);
      if (_buffer.length < newline + 1 + length) break;
      final payload = utf8.decode(
        _buffer.sublist(newline + 1, newline + 1 + length),
        allowMalformed: true,
      );
      offset = newline + 1 + length;
      _handle(
        header[0],
        int.parse(header[1]),
        int.parse(header[2]),
        int.parse(header[3]),
        payload,
      );
    }
    _buffer = _buffer.sublist(offset);
  }

  void _handle(String name, int a, int b, int c, String payload) {
    switch (name) {
      case 'ready':
        _ready.complete();
      case 'view':
        _creating.remove(a)?.complete(b);
      case 'created':
        final parts = payload.split('\n');
        _created.add(
          ExtensionContext(
            contextId: a,
            viewId: b < 0 ? null : b,
            extensionUuid: parts[0],
            url: parts.sublist(1).join('\n'),
            isTopLevel: c != 0,
          ),
        );
      case 'destroyed':
        _destroyed.add(a);
      case 'message':
        _messages.add(TransportMessage(a, payload));
      case 'intercept':
        _intercepts.add((request: a, view: b, details: payload));
      case 'url':
        _viewEvents.add((view: a, url: payload, loading: null));
      case 'loading':
        _viewEvents.add((view: a, url: null, loading: b != 0));
    }
  }

  void _command(String name, {int a = 0, String payload = ''}) {
    if (_stopping || crashed.isCompleted) return;
    final bytes = utf8.encode(payload);
    _process.stdin.add(ascii.encode('$name $a 0 0 ${bytes.length}\n'));
    _process.stdin.add(bytes);
  }

  Future<int> createView() {
    final request = _nextRequest++;
    final completer = _creating[request] = Completer<int>();
    _command('create', a: request);
    return completer.future.timeout(const Duration(seconds: 30));
  }

  void navigate(int view, String url) =>
      _command('navigate', a: view, payload: url);

  void destroyView(int view) => _command('destroy', a: view);

  void startIntercepting() => _command('intercepting');

  void answerIntercept(int request, String verdict) =>
      _command('verdict', a: request, payload: verdict);

  @override
  void setState(String json) => _command('state', payload: json);

  @override
  bool send(int contextId, String payload) {
    _command('send', a: contextId, payload: payload);
    return true;
  }

  Future<void> stop() async {
    // Give what is on its way to disk time to get there.
    await Future<void>.delayed(const Duration(seconds: 1));
    _command('quit');
    _stopping = true;
    await _process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -9;
      },
    );
    await _log.close();
  }
}
