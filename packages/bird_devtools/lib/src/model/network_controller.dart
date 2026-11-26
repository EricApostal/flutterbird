import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import 'tool_controller.dart';

class HttpHeader {
  const HttpHeader(this.name, this.value);
  final String name;
  final String value;
}

class ResponseContent {
  const ResponseContent({
    required this.text,
    required this.base64Encoded,
    required this.mimeType,
    required this.size,
    this.truncated = false,
  });

  final String text;
  final bool base64Encoded;
  final String mimeType;
  final int size;
  final bool truncated;

  Uint8List get bytes {
    if (!base64Encoded) return utf8.encode(text);
    try {
      return base64.decode(text);
    } on FormatException {
      return Uint8List(0);
    }
  }

  /// The body as text, or null if it is not text.
  String? get asText {
    if (!base64Encoded) return text;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
}

class HttpCookie {
  const HttpCookie(this.name, this.value, [this.attributes = const {}]);
  final String name;
  final String value;
  final Map<String, String> attributes;
}

class RequestTimings {
  const RequestTimings(this.parts, this.total);

  /// Milliseconds by phase, in the order the phases happen.
  final Map<String, double> parts;
  final double total;
}

enum NetworkCategory { html, css, js, xhr, fonts, images, media, websocket, other }

class NetworkRequest {
  NetworkRequest({
    required this.actor,
    required this.resourceId,
    required this.url,
    required this.method,
    required this.started,
    required this.causeType,
    required this.isXhr,
    required this.isNavigation,
    required this.referrerPolicy,
    required this.priority,
    required this.index,
  }) : uri = Uri.tryParse(url);

  final String actor;
  final int resourceId;
  final String url;
  final Uri? uri;
  final String method;
  final DateTime started;
  final String causeType;
  final bool isXhr;
  final bool isNavigation;
  final String referrerPolicy;
  final int priority;
  final int index;

  int? status;
  String statusText = '';
  String mimeType = '';
  String httpVersion = '';
  int headersSize = 0;
  int? contentSize;
  int? transferredSize;
  double? totalMs;
  bool fromCache = false;
  bool complete = false;

  List<HttpHeader>? requestHeaders;
  List<HttpHeader>? responseHeaders;
  String? postData;
  ResponseContent? content;
  RequestTimings? timings;

  /// Why details could not be had, if they could not.
  String? detailsError;

  bool get failed => complete && (status == null || status == 0);

  bool get isError => failed || (status ?? 0) >= 400;

  String get host {
    final uri = this.uri;
    if (uri == null) return '';
    if (uri.host.isEmpty) return '';
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  String get fileName {
    final uri = this.uri;
    if (uri == null) return url;
    if (uri.scheme == 'data') {
      return url.length > 60 ? '${url.substring(0, 60)}…' : url;
    }
    final segments = uri.pathSegments.where((part) => part.isNotEmpty);
    var name = segments.isEmpty ? '/' : segments.last;
    if (uri.hasQuery) name += '?${uri.query}';
    return name;
  }

  String get typeLabel {
    final mime = mimeType.split(';').first.trim();
    if (mime.isEmpty) return '';
    final sub = mime.split('/').last;
    return switch (sub) {
      'javascript' || 'x-javascript' || 'ecmascript' => 'js',
      'plain' => 'plain',
      'svg+xml' => 'svg',
      'x-icon' || 'vnd.microsoft.icon' => 'ico',
      'octet-stream' => 'octet-stream',
      _ => sub.replaceFirst('x-', ''),
    };
  }

  NetworkCategory get category {
    if (uri?.scheme == 'ws' || uri?.scheme == 'wss') {
      return NetworkCategory.websocket;
    }
    if (isXhr) return NetworkCategory.xhr;
    final mime = mimeType.toLowerCase();
    if (causeType == 'stylesheet' || mime.startsWith('text/css')) {
      return NetworkCategory.css;
    }
    if (causeType == 'script' || mime.contains('javascript')) {
      return NetworkCategory.js;
    }
    if (mime.startsWith('font/') ||
        causeType == 'font' ||
        RegExp(r'\.(woff2?|ttf|otf)$').hasMatch(uri?.path ?? '')) {
      return NetworkCategory.fonts;
    }
    if (mime.startsWith('image/') || causeType == 'image') {
      return NetworkCategory.images;
    }
    if (mime.startsWith('audio/') ||
        mime.startsWith('video/') ||
        causeType == 'audio' ||
        causeType == 'video') {
      return NetworkCategory.media;
    }
    if (mime.startsWith('text/html') ||
        causeType == 'document' ||
        causeType == 'iframe') {
      return NetworkCategory.html;
    }
    return NetworkCategory.other;
  }

  String? header(List<HttpHeader>? headers, String name) {
    final lower = name.toLowerCase();
    for (final header in headers ?? const <HttpHeader>[]) {
      if (header.name.toLowerCase() == lower) return header.value;
    }
    return null;
  }

  /// The cookies the request sent. The engine does not list them itself, so
  /// they are read out of the headers.
  List<HttpCookie> get requestCookies {
    final value = header(requestHeaders, 'cookie');
    if (value == null) return const [];
    return [
      for (final pair in value.split(';'))
        if (pair.contains('='))
          HttpCookie(
            pair.substring(0, pair.indexOf('=')).trim(),
            pair.substring(pair.indexOf('=') + 1).trim(),
          ),
    ];
  }

  List<HttpCookie> get responseCookies => [
    for (final header in responseHeaders ?? const <HttpHeader>[])
      if (header.name.toLowerCase() == 'set-cookie')
        ?_parseSetCookie(header.value),
  ];

  static HttpCookie? _parseSetCookie(String value) {
    final parts = value.split(';');
    final first = parts.first;
    final equals = first.indexOf('=');
    if (equals < 0) return null;
    return HttpCookie(
      first.substring(0, equals).trim(),
      first.substring(equals + 1).trim(),
      {
        for (final part in parts.skip(1))
          if (part.trim().isNotEmpty)
            part.split('=').first.trim(): part.contains('=')
                ? part.substring(part.indexOf('=') + 1).trim()
                : 'true',
      },
    );
  }

  static String _shellQuote(String text) =>
      "'${text.replaceAll("'", r"'\''")}'";

  String get asCurl {
    final out = StringBuffer('curl ${_shellQuote(url)}');
    if (method != 'GET' && !(method == 'POST' && (postData ?? '').isNotEmpty)) {
      out.write(' -X ${_shellQuote(method)}');
    }
    for (final header in requestHeaders ?? const <HttpHeader>[]) {
      if (header.name.startsWith(':')) continue;
      out.write(' \\\n  -H ${_shellQuote('${header.name}: ${header.value}')}');
    }
    if ((postData ?? '').isNotEmpty) {
      out.write(' \\\n  --data-raw ${_shellQuote(postData!)}');
    }
    return out.toString();
  }

  String get asFetch {
    const encoder = JsonEncoder.withIndent('  ');
    return 'await fetch(${jsonEncode(url)}, ${encoder.convert({
      'method': method,
      'headers': {for (final header in requestHeaders ?? const <HttpHeader>[]) header.name: header.value},
      if ((postData ?? '').isNotEmpty) 'body': postData,
      'credentials': 'include',
    })});';
  }

  String headersText(List<HttpHeader>? headers) =>
      (headers ?? const []).map((h) => '${h.name}: ${h.value}').join('\n');
}

class NetworkController extends ToolController {
  NetworkController(super.session);

  static const int _maxRequests = 5000;

  final List<NetworkRequest> requests = [];
  final Map<int, NetworkRequest> _byResourceId = {};
  int _nextIndex = 0;

  bool recording = true;
  NetworkRequest? selected;
  String _filterText = '';
  int revision = 0;

  /// The tab of the detail sidebar that is showing.
  String detailTab = 'headers';

  /// When the load being shown began, and how far into it its events came.
  DateTime? navigationStart;
  int? domContentLoadedMs;
  int? loadMs;

  bool get persistLogs => session.settings.flag('network.persist');
  set persistLogs(bool value) {
    session.settings.set('network.persist', value);
    _touch();
  }

  String get filterText => _filterText;
  set filterText(String value) {
    _filterText = value;
    _touch();
  }

  /// The type buttons that are on. None on means "All".
  Set<NetworkCategory> get categories => {
    for (final name in session.settings.strings('network.categories'))
      ...NetworkCategory.values.where((c) => c.name == name),
  };

  /// Chooses one type, or with [additive] adds to what is chosen. Null is All.
  void chooseCategory(NetworkCategory? category, {bool additive = false}) {
    var next = categories;
    if (category == null) {
      next = {};
    } else if (!additive) {
      next = {category};
    } else if (!next.remove(category)) {
      next.add(category);
    }
    session.settings.set('network.categories', [for (final c in next) c.name]);
    _touch();
  }

  String get sortColumn => session.settings.text('network.sort', 'waterfall');
  bool get sortAscending => session.settings.flag('network.ascending', true);

  void sortBy(String column) {
    final ascending = column == sortColumn ? !sortAscending : true;
    session.settings
      ..set('network.sort', column)
      ..set('network.ascending', ascending);
    _touch();
  }

  List<NetworkRequest>? _visible;

  List<NetworkRequest> get visibleRequests {
    final cached = _visible;
    if (cached != null) return cached;
    final categories = this.categories;
    final matches = _matcher(_filterText);
    final visible = [
      for (final request in requests)
        if ((categories.isEmpty || categories.contains(request.category)) &&
            matches(request))
          request,
    ];
    int compare(NetworkRequest a, NetworkRequest b) => switch (sortColumn) {
      'status' => (a.status ?? 0).compareTo(b.status ?? 0),
      'method' => a.method.compareTo(b.method),
      'domain' => a.host.compareTo(b.host),
      'file' => a.fileName.compareTo(b.fileName),
      'initiator' => a.causeType.compareTo(b.causeType),
      'type' => a.typeLabel.compareTo(b.typeLabel),
      'transferred' => (a.transferredSize ?? 0).compareTo(
        b.transferredSize ?? 0,
      ),
      'size' => (a.contentSize ?? 0).compareTo(b.contentSize ?? 0),
      'duration' => (a.totalMs ?? 0).compareTo(b.totalMs ?? 0),
      _ => a.started.compareTo(b.started),
    };
    visible.sort((a, b) {
      var order = compare(a, b);
      if (order == 0) order = a.index.compareTo(b.index);
      return sortAscending ? order : -order;
    });
    return _visible = visible;
  }

  /// Firefox's filter language, as much of it as the engine can answer:
  /// `method:`, `status-code:`, `domain:`, `mime-type:`, `scheme:`, a leading
  /// `-` to leave out, `regexp:`, and plain words in the address.
  bool Function(NetworkRequest) _matcher(String filter) {
    final terms = filter
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return (_) => true;
    final tests = <bool Function(NetworkRequest)>[];
    for (var term in terms) {
      final negated = term.startsWith('-') && term.length > 1;
      if (negated) term = term.substring(1);
      final colon = term.indexOf(':');
      final key = colon > 0 ? term.substring(0, colon).toLowerCase() : '';
      final value = term.substring(colon + 1).toLowerCase();
      bool Function(NetworkRequest) test;
      switch (key) {
        case 'method':
          test = (r) => r.method.toLowerCase() == value;
        case 'status-code':
          test = (r) => '${r.status}'.startsWith(value);
        case 'domain':
          test = (r) => r.host.toLowerCase().contains(value);
        case 'mime-type':
          test = (r) => r.mimeType.toLowerCase().contains(value);
        case 'scheme':
          test = (r) => r.uri?.scheme == value;
        case 'regexp':
          try {
            final pattern = RegExp(
              term.substring(colon + 1),
              caseSensitive: false,
            );
            test = (r) => pattern.hasMatch(r.url);
          } on FormatException {
            continue;
          }
        default:
          final needle = term.toLowerCase();
          test = (r) => r.url.toLowerCase().contains(needle);
      }
      tests.add(negated ? (r) => !test(r) : test);
    }
    return (request) => tests.every((test) => test(request));
  }

  void _touch() {
    _visible = null;
    revision++;
    changed();
  }

  void clear() {
    requests.clear();
    _byResourceId.clear();
    selected = null;
    navigationStart = null;
    domContentLoadedMs = null;
    loadMs = null;
    _touch();
  }

  void setRecording(bool value) {
    recording = value;
    _touch();
  }

  void select(NetworkRequest? request) {
    selected = request;
    changed();
    if (request != null) loadDetails(request, content: true);
  }

  @override
  void onWillNavigate(String url) {
    if (!persistLogs) clear();
    navigationStart = DateTime.now();
    domContentLoadedMs = null;
    loadMs = null;
    _touch();
  }

  @override
  void onDocumentComplete() {
    // An engine without the fix drops what it learns of a navigation's request
    // once the new document's actors replace the old ones.
    for (final request in requests) {
      if (request.isNavigation && !request.complete && request.status != null) {
        request.complete = true;
      }
    }
    _touch();
    _loadPageTimings();
  }

  Future<void> _loadPageTimings() async {
    try {
      // The load event has yet to finish when the document is complete.
      for (var attempt = 0; attempt < 4; attempt++) {
        final result = await session.runInPage(
          'const t = performance.timing;'
          'return [t.domContentLoadedEventEnd - t.navigationStart, t.loadEventEnd - t.navigationStart];',
        );
        if (result is List && result.length == 2) {
          final dom = (result[0] as num).toInt();
          final load = (result[1] as num).toInt();
          if (dom >= 0) domContentLoadedMs = dom;
          if (load >= 0) {
            loadMs = load;
            break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (isDisposed) return;
      }
      _touch();
    } catch (_) {
      // The footer does without them.
    }
  }

  @override
  void onResources(String type, List<Map<String, Object?>> resources) {
    if (type != 'network-event' || !recording) return;
    for (final resource in resources) {
      final request = NetworkRequest(
        actor: resource.str('actor'),
        resourceId: resource.integer('resourceId'),
        url: resource.str('url'),
        method: resource.str('method'),
        started: DateTime.fromMillisecondsSinceEpoch(
          resource.integer('timeStamp'),
        ),
        causeType: resource.obj('cause').str('type'),
        isXhr: resource.flag('isXHR'),
        isNavigation: resource.flag('isNavigationRequest'),
        referrerPolicy: resource.str('referrerPolicy'),
        priority: resource.integer('priority'),
        index: _nextIndex++,
      )..fromCache = resource.flag('fromCache');
      requests.add(request);
      if (requests.length > _maxRequests) requests.removeAt(0);
      // The engine reuses these numbers across processes: the latest one with
      // a number is the one its updates are about.
      _byResourceId[request.resourceId] = request;
      session.console.addNetworkRequest(request);
    }
    _touch();
  }

  @override
  void onResourceUpdates(String type, List<Map<String, Object?>> updates) {
    if (type != 'network-event') return;
    for (final update in updates) {
      final request = _byResourceId[update.integer('resourceId')];
      if (request == null) continue;
      final values = update.obj('resourceUpdates');
      if (values.containsKey('status')) {
        request
          ..status = values.integer('status')
          ..statusText = values.str('statusText')
          ..mimeType = values.str('mimeType')
          ..httpVersion = values.str('httpVersion')
          ..headersSize = values.integer('headersSize')
          ..fromCache = values.flag('fromCache');
        // Fetched at once: an engine without the persistence fix drops these
        // actors as soon as the page finishes loading.
        loadDetails(request);
      }
      if (values.containsKey('contentSize')) {
        final reported = values.number('totalTime');
        request
          ..contentSize = values.integer('contentSize')
          ..transferredSize = values.integer('transferredSize')
          ..totalMs = math.max(0, reported)
          ..complete = true;
        if (selected == request) loadDetails(request, content: true);
      }
    }
    _touch();
    session.console.networkChanged();
  }

  final Set<String> _loading = {};

  Future<void> loadDetails(NetworkRequest request, {bool content = false}) async {
    Future<void> fetch(
      String type,
      bool needed,
      void Function(Map<String, Object?>) apply,
    ) async {
      if (!needed || !_loading.add('${request.actor} $type')) return;
      try {
        apply(await session.connection.request(request.actor, type));
        _touch();
      } on RdpError catch (error) {
        if (error.isUnknownActor) {
          request.detailsError =
              'The engine no longer holds the details of this request.';
          _touch();
        }
      } finally {
        _loading.remove('${request.actor} $type');
      }
    }

    List<HttpHeader> headers(Map<String, Object?> response) => [
      for (final header in response.maps('headers'))
        HttpHeader(header.str('name'), header.str('value')),
    ];

    await Future.wait([
      fetch('getRequestHeaders', request.requestHeaders == null, (response) {
        request.requestHeaders = headers(response);
      }),
      fetch(
        'getResponseHeaders',
        request.responseHeaders == null && request.status != null,
        (response) => request.responseHeaders = headers(response),
      ),
      fetch(
        'getRequestPostData',
        content && request.postData == null && request.method != 'GET',
        (response) => request.postData = response.obj('postData').str('text'),
      ),
      fetch(
        'getEventTimings',
        request.complete && request.timings == null,
        (response) {
          final parts = response.obj('timings');
          request.timings = RequestTimings({
            for (final phase in const [
              'blocked',
              'dns',
              'connect',
              'ssl',
              'send',
              'wait',
              'receive',
            ])
              phase: math.max(0, parts.number(phase)),
          }, math.max(0, response.number('totalTime')));
        },
      ),
      fetch(
        'getResponseContent',
        content && request.complete && request.content == null,
        (response) {
          final body = response.obj('content');
          request.content = ResponseContent(
            text: body.str('text'),
            base64Encoded: body.str('encoding') == 'base64',
            mimeType: body.str('mimeType'),
            size: body.integer('size'),
            truncated: response.flag('contentDiscarded'),
          );
        },
      ),
    ]);
  }

  /// Sends the request again, from the page.
  Future<void> resend(NetworkRequest request) async {
    await loadDetails(request, content: true);
    const forbidden = {
      'host',
      'cookie',
      'origin',
      'referer',
      'user-agent',
      'content-length',
      'connection',
      'accept-encoding',
    };
    final headers = {
      for (final header in request.requestHeaders ?? const <HttpHeader>[])
        if (!forbidden.contains(header.name.toLowerCase()) &&
            !header.name.toLowerCase().startsWith('sec-'))
          header.name: header.value,
    };
    final options = {
      'method': request.method,
      'headers': headers,
      if ((request.postData ?? '').isNotEmpty && request.method != 'GET')
        'body': request.postData,
      'credentials': 'include',
    };
    await session.runInPage(
      'fetch(${jsonEncode(request.url)}, ${jsonEncode(options)}).catch(() => {}); return true;',
    );
  }

  int get totalContentSize =>
      visibleRequests.fold(0, (sum, r) => sum + (r.contentSize ?? 0));

  int get totalTransferredSize => visibleRequests.fold(
    0,
    (sum, r) => sum + (r.fromCache ? 0 : (r.transferredSize ?? 0)),
  );

  /// From the first request's start to the last one's end.
  Duration get finishTime {
    final shown = visibleRequests;
    if (shown.isEmpty) return Duration.zero;
    var first = shown.first.started;
    var last = shown.first.started;
    for (final request in shown) {
      if (request.started.isBefore(first)) first = request.started;
      final end = request.started.add(
        Duration(microseconds: ((request.totalMs ?? 0) * 1000).round()),
      );
      if (end.isAfter(last)) last = end;
    }
    return last.difference(first);
  }

  /// Everything shown, as an HTTP Archive.
  String exportHar() {
    List<Map<String, String>> pairs(List<HttpHeader>? headers) => [
      for (final header in headers ?? const <HttpHeader>[])
        {'name': header.name, 'value': header.value},
    ];
    return const JsonEncoder.withIndent('  ').convert({
      'log': {
        'version': '1.2',
        'creator': {'name': 'Rubisco Browser DevTools', 'version': '0.1'},
        'entries': [
          for (final request in visibleRequests)
            {
              'startedDateTime': request.started.toUtc().toIso8601String(),
              'time': request.totalMs ?? 0,
              'request': {
                'method': request.method,
                'url': request.url,
                'httpVersion': request.httpVersion,
                'headers': pairs(request.requestHeaders),
                'cookies': [
                  for (final c in request.requestCookies)
                    {'name': c.name, 'value': c.value},
                ],
                'queryString': [
                  for (final e
                      in request.uri?.queryParameters.entries ??
                          const <MapEntry<String, String>>[])
                    {'name': e.key, 'value': e.value},
                ],
                if ((request.postData ?? '').isNotEmpty)
                  'postData': {'mimeType': '', 'text': request.postData},
                'headersSize': -1,
                'bodySize': request.postData?.length ?? 0,
              },
              'response': {
                'status': request.status ?? 0,
                'statusText': request.statusText,
                'httpVersion': request.httpVersion,
                'headers': pairs(request.responseHeaders),
                'cookies': [
                  for (final c in request.responseCookies)
                    {'name': c.name, 'value': c.value},
                ],
                'content': {
                  'size': request.contentSize ?? 0,
                  'mimeType': request.mimeType,
                  if (request.content != null) 'text': request.content!.text,
                  if (request.content?.base64Encoded ?? false)
                    'encoding': 'base64',
                },
                'redirectURL':
                    request.header(request.responseHeaders, 'location') ?? '',
                'headersSize': request.headersSize,
                'bodySize': request.transferredSize ?? 0,
              },
              'cache': <String, Object>{},
              'timings': {
                for (final part
                    in request.timings?.parts.entries ??
                        const <MapEntry<String, double>>[])
                  part.key: part.value,
              },
            },
        ],
      },
    });
  }
}
