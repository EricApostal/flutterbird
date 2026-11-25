import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../extension_registry.dart';
import 'api.dart';
import 'extension_host.dart';
import 'extension_transport.dart';

/// A native messaging host an application installed for browsers to find.
class NativeHostManifest {
  const NativeHostManifest({
    required this.name,
    required this.path,
    required this.file,
    required this.allowedExtensions,
  });

  final String name;

  /// The program to run.
  final String path;

  /// The manifest this came from, which the program is told about.
  final File file;

  /// The ids of the extensions that may talk to the program.
  final List<String> allowedExtensions;
}

/// Finds native messaging hosts where Firefox looks for them, so that the
/// hosts applications install for Firefox work here as they are.
class NativeHostLocator {
  NativeHostLocator({List<Directory>? directories})
    : directories = directories ?? defaultDirectories();

  /// Where the manifests are looked for, first match wins.
  final List<Directory> directories;

  /// A host name is dot-separated words, which also keeps it from naming a
  /// path.
  static final RegExp _validName = RegExp(r'^\w+(\.\w+)*$');

  static List<Directory> defaultDirectories({
    Map<String, String>? environment,
    String? platform,
  }) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'];
    final system = platform ?? Platform.operatingSystem;

    switch (system) {
      case 'macos':
        return [
          if (home != null)
            Directory('$home/Library/Application Support/Mozilla/NativeMessagingHosts'),
          Directory('/Library/Application Support/Mozilla/NativeMessagingHosts'),
        ];
      case 'linux':
        return [
          if (home != null) Directory('$home/.mozilla/native-messaging-hosts'),
          Directory('/usr/lib/mozilla/native-messaging-hosts'),
          Directory('/usr/lib64/mozilla/native-messaging-hosts'),
          Directory('/usr/share/mozilla/native-messaging-hosts'),
        ];
      default:
        // Windows keeps them in the registry, which is not read here.
        return const [];
    }
  }

  /// The host called [name], or null when none is installed or the one
  /// installed is not a usable manifest.
  Future<NativeHostManifest?> find(String name) async {
    if (!_validName.hasMatch(name)) return null;

    for (final directory in directories) {
      final file = File('${directory.path}/$name.json');
      try {
        if (!await file.exists()) continue;
        final json = jsonDecode(await file.readAsString());
        if (json is! Map) continue;

        final path = json['path'];
        final type = json['type'];
        final allowed = json['allowed_extensions'];
        if (json['name'] != name ||
            type != 'stdio' ||
            path is! String ||
            !path.startsWith('/') ||
            allowed is! List) {
          continue;
        }
        return NativeHostManifest(
          name: name,
          path: path,
          file: file,
          allowedExtensions: allowed.whereType<String>().toList(),
        );
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}

/// Starts a native messaging host's program.
typedef NativeProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<Process> _startProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.start(
  executable,
  arguments,
  workingDirectory: workingDirectory,
);

/// What the browser reads from a native host at most, in one message.
const int _maxMessageFromHost = 1024 * 1024;

/// `browser.runtime.connectNative` and `sendNativeMessage`: talking to a
/// program installed on the computer, such as a password manager's app.
///
/// The program is the one an application registered for the extension, and
/// only for an extension whose id the registration lists. It is started with
/// the path of its manifest and the extension's id, and exchanges JSON
/// messages over its standard input and output, each after a four byte length
/// in the computer's byte order, as Firefox does.
class NativeMessagingApi extends ApiNamespace implements ContextObserver {
  NativeMessagingApi({NativeHostLocator? locator, NativeProcessStarter? start})
    : _locator = locator ?? NativeHostLocator(),
      _start = start ?? _startProcess;

  final NativeHostLocator _locator;
  final NativeProcessStarter _start;

  /// "context/port" -> the connection, once the program has started.
  final Map<String, Future<_Connection?>> _connections = {};

  @override
  String get name => 'native';

  @override
  String? get requiredPermission => 'nativeMessaging';

  @override
  void detach() {
    for (final connection in _connections.values.toList()) {
      unawaited(connection.then((open) => open?.close()));
    }
    _connections.clear();
  }

  @override
  void contextCreated(ExtensionHost host, ExtensionContext context) {}

  @override
  void documentEvent(
    ExtensionHost host,
    ExtensionContext context,
    String name,
  ) {}

  @override
  void contextDestroyed(ExtensionHost host, ExtensionContext context) {
    final prefix = '${context.contextId}/';
    for (final key in _connections.keys.toList()) {
      if (!key.startsWith(prefix)) continue;
      final connection = _connections.remove(key);
      if (connection != null) {
        unawaited(connection.then((open) => open?.close()));
      }
    }
  }

  @override
  Future<void> extensionRemoved(InstalledExtension extension) async {
    // Nothing is kept per extension: connections end with their contexts.
  }

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'connect':
        return _connect(call);
      case 'post':
        return _post(call);
      case 'close':
        final key = _key(call, call.arg(0));
        final connection = _connections.remove(key);
        if (connection != null) await (await connection)?.close();
        return null;
      case 'send':
        return _sendOnce(call);
      default:
        throw ApiException('runtime.${call.method} is not supported');
    }
  }

  String _key(ApiCall call, Object? portId) =>
      '${call.context.contextId}/$portId';

  Future<(NativeHostManifest, Process)> _launch(
    ApiCall call,
    Object? application,
  ) async {
    if (application is! String) {
      throw ApiException('The name of a native application is required');
    }

    final manifest = await _locator.find(application);
    call.host.note(
      () =>
          'native: ${call.context.contextId} asks for $application: '
          '${manifest == null ? 'no such host' : manifest.path}',
    );
    if (manifest == null) {
      throw ApiException('No such native application $application');
    }
    if (!manifest.allowedExtensions.contains(call.extension.id)) {
      call.host.note(
        () =>
            'native: ${call.extension.id} is not in the allowed extensions of '
            '$application (${manifest.allowedExtensions.join(', ')})',
      );
      throw ApiException(
        'This extension does not have permission to use native application '
        '$application',
      );
    }

    try {
      final process = await _start(
        manifest.path,
        [manifest.file.path, call.extension.id],
        workingDirectory: File(manifest.path).parent.path,
      );
      call.host.note(() => 'native: started ${manifest.path} (pid ${process.pid})');
      return (manifest, process);
    } on ProcessException catch (error) {
      call.host.note(() => 'native: could not start ${manifest.path}: ${error.message}');
      throw ApiException(
        'Error occurred while starting native application $application: '
        '${error.message}',
      );
    }
  }

  Future<Object?> _connect(ApiCall call) {
    final portId = call.arg(1);
    if (portId is! String) {
      throw ApiException('runtime.connectNative needs a port id');
    }
    final key = _key(call, portId);

    final started = () async {
      final (_, process) = await _launch(call, call.arg(0));
      return _Connection(call.host, call.context.contextId, portId, process);
    }();

    // A message can follow the connect before the program has started, so the
    // connection is known as soon as it is asked for.
    final tracked = started.then<_Connection?>((c) => c).catchError((_) => null);
    _connections[key] = tracked;

    return started.then((_) => null);
  }

  Future<Object?> _post(ApiCall call) async {
    final connection = _connections[_key(call, call.arg(0))];
    final open = connection == null ? null : await connection;
    open?.send(call.arg(1));
    return null;
  }

  Future<Object?> _sendOnce(ApiCall call) async {
    final (_, process) = await _launch(call, call.arg(0));
    final connection = _Connection.oneShot(process);

    try {
      connection.send(call.arg(1));
      return await connection.firstMessage.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw ApiException('The native application did not answer'),
      );
    } finally {
      await connection.close();
    }
  }
}

/// A running native host and what it says.
class _Connection {
  _Connection(this._host, this._contextId, this._portId, this._process) {
    _listen();
  }

  _Connection.oneShot(this._process)
    : _host = null,
      _contextId = null,
      _portId = null {
    _listen();
  }

  final ExtensionHost? _host;
  final int? _contextId;
  final String? _portId;
  final Process _process;

  final BytesBuilder _incoming = BytesBuilder(copy: false);

  /// The last message of the program, kept while it is short enough to be a
  /// status or an error and not data.
  String? _lastShort;
  final Completer<Object?> _first = Completer<Object?>();
  bool _closed = false;

  /// The first message the program sends, for `sendNativeMessage`.
  Future<Object?> get firstMessage => _first.future;

  void _listen() {
    // Nobody waits for the first message of a connection that is not a
    // one-shot, and that must not be an error nobody handles.
    _first.future.ignore();
    _process.stdout.listen(
      _onData,
      onDone: _onExit,
      onError: (_) => _onExit(),
      cancelOnError: true,
    );
    // What the program writes to its error output is read, or it can block on
    // writing it, and is kept in the trace: it is where a host says why it
    // will not talk.
    _process.stderr
        .transform(utf8.decoder)
        .listen(
          (text) => _host?.note(() => 'native: pid ${_process.pid} says: ${text.trim()}'),
          onError: (_) {},
        );
    unawaited(_process.stdin.done.catchError((_) {}));
    unawaited(
      _process.exitCode.then((code) {
        _host?.note(() => 'native: pid ${_process.pid} exited with $code');
        final last = _lastShort;
        if (code != 0 && last != null) {
          _host?.note(() => 'native: pid ${_process.pid} last said $last');
        }
        _onExit();
      }),
    );
  }

  void _onData(List<int> data) {
    _incoming.add(data);

    while (true) {
      final bytes = _incoming.toBytes();
      if (bytes.length < 4) return;

      final length = ByteData.sublistView(bytes).getUint32(0, Endian.host);
      if (length > _maxMessageFromHost) {
        // A host that sends more than a browser reads is not behaving.
        unawaited(close(notify: true));
        return;
      }
      if (bytes.length < 4 + length) return;

      final body = bytes.sublist(4, 4 + length);
      _incoming.clear();
      if (bytes.length > 4 + length) {
        _incoming.add(bytes.sublist(4 + length));
      }

      final Object? message;
      try {
        message = jsonDecode(utf8.decode(body));
      } on FormatException {
        unawaited(close(notify: true));
        return;
      }
      _deliver(message);
    }
  }

  void _deliver(Object? message) {
    final text = jsonEncode(message);
    _lastShort = text.length <= 256 ? text : null;
    _host?.note(
      () => 'native: pid ${_process.pid} sent ${text.length} characters',
    );
    if (!_first.isCompleted) _first.complete(message);
    final host = _host;
    if (host != null && !_closed) {
      host.dispatchEvent(_contextId!, 'bird.nativeMessage', [_portId, message]);
    }
  }

  void _onExit() {
    if (_closed) return;
    _closed = true;
    final host = _host;
    if (host != null) {
      host.dispatchEvent(_contextId!, 'bird.nativeDisconnect', [_portId, null]);
    }
    if (!_first.isCompleted) {
      _first.completeError(
        ApiException('The native application exited without answering'),
      );
    }
  }

  /// Sends [message] to the program, as a length and then JSON.
  void send(Object? message) {
    if (_closed) return;
    final body = utf8.encode(jsonEncode(message));
    _host?.note(() => 'native: sending ${body.length} bytes to pid ${_process.pid}');
    final header = ByteData(4)..setUint32(0, body.length, Endian.host);
    try {
      _process.stdin
        ..add(header.buffer.asUint8List())
        ..add(body);
    } on Object {
      unawaited(close());
    }
  }

  Future<void> close({bool notify = false}) async {
    if (_closed) {
      _process.kill();
      return;
    }
    _closed = true;
    final host = _host;
    if (notify && host != null) {
      host.dispatchEvent(_contextId!, 'bird.nativeDisconnect', [_portId, null]);
    }
    if (!_first.isCompleted) {
      _first.completeError(ApiException('The native application was closed'));
    }
    try {
      await _process.stdin.close();
    } on Object {
      // The program may be gone already.
    }
    _process.kill();
  }
}
