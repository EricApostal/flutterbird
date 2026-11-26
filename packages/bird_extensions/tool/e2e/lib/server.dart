import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef Report = ({bool ok, String detail});

/// Serves the pages the tests browse, and collects what they say happened.
class TestServer {
  TestServer._(this._server);

  final HttpServer _server;
  final Map<String, Report> reports = {};

  /// Every path that was asked for, which is how a test knows that a request
  /// which was meant to be blocked never left the browser.
  final List<String> requests = [];
  final _arrived = StreamController<String>.broadcast();

  int get port => _server.port;
  String get origin => 'http://127.0.0.1:$port';

  static Future<TestServer> start(Directory pages) async {
    final server = TestServer._(
      await HttpServer.bind(InternetAddress.anyIPv4, 0),
    );
    server._server.listen((request) => server._handle(request, pages));
    return server;
  }

  Future<void> _handle(HttpRequest request, Directory pages) async {
    final path = request.uri.path;
    final response = request.response;
    response.headers
      ..set('Cache-Control', 'no-store')
      ..set('Access-Control-Allow-Origin', '*');
    try {
      if (path == '/report') {
        if (request.method == 'POST') {
          final body = jsonDecode(await utf8.decodeStream(request)) as Map;
          final name = body['name'] as String;
          reports[name] = (
            ok: body['ok'] == true,
            detail: '${body['detail'] ?? ''}',
          );
          _arrived.add(name);
        }
        response.statusCode = 204;
      } else {
        requests.add(path);
        await _serve(request, pages, path);
      }
    } on Object catch (error) {
      response.statusCode = 500;
      response.write('$error');
    }
    await response.close();
  }

  Future<void> _serve(HttpRequest request, Directory pages, String path) async {
    final response = request.response;
    if (path.startsWith('/net/')) {
      final name = path.substring('/net/'.length);
      if (name.startsWith('headers')) {
        response.write(request.headers.value('x-bird-added') ?? 'missing');
      } else if (name.endsWith('.js')) {
        response.headers.contentType = ContentType('text', 'javascript');
        final flag = name.replaceAll(RegExp('[^a-z]'), '_');
        response.write('window["loaded_$flag"] = true;');
      } else if (name.endsWith('.png')) {
        response.headers.contentType = ContentType('image', 'png');
        response.add(_onePixel);
      } else {
        response.write(name);
      }
      return;
    }

    // The same few files serve every page: /page/<name> is <name>.html.
    var file = path.substring(1);
    if (path.startsWith('/page/')) file = '${path.substring(6)}.html';
    if (path.startsWith('/frame/')) file = 'frame.html';
    final source = File('${pages.path}/$file');
    if (file.contains('..') || !await source.exists()) {
      response.statusCode = 404;
      return;
    }
    response.headers.contentType = file.endsWith('.js')
        ? ContentType('text', 'javascript')
        : ContentType.html;
    if (path == '/page/strict') {
      // What a site like YouTube sends: only its own scripts, and no strings
      // where a script or markup is expected.
      response.headers.set(
        'Content-Security-Policy',
        "script-src 'self' 'nonce-bird'; object-src 'none'; "
            "require-trusted-types-for 'script'",
      );
    }
    response.write(
      (await source.readAsString()).replaceAll('{{PORT}}', '$port'),
    );
  }

  /// Waits for each of [names], and returns those that never came.
  Future<Set<String>> waitFor(
    Iterable<String> names, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final missing = {...names}..removeWhere(reports.containsKey);
    if (missing.isEmpty) return missing;
    final done = Completer<void>();
    final subscription = _arrived.stream.listen((name) {
      missing.remove(name);
      if (missing.isEmpty && !done.isCompleted) done.complete();
    });
    await done.future.timeout(timeout, onTimeout: () {});
    await subscription.cancel();
    return missing;
  }

  Future<void> close() => _server.close(force: true);

  static final List<int> _onePixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==',
  );
}
