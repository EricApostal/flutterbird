import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A network failure, or a response that was not usable.
class FetchException implements Exception {
  FetchException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'FetchException: $message';
}

/// The two HTTP operations the installer needs, as an interface so that the
/// install pipeline can be tested without a network.
abstract class HttpFetcher {
  Future<Object?> getJson(Uri url);

  /// Downloads [url]. Fails as soon as more than [maxBytes] have arrived
  /// rather than reading the whole of an oversized body first.
  Future<Uint8List> getBytes(
    Uri url, {
    required int maxBytes,
    void Function(int received, int? total)? onProgress,
  });
}

/// An [HttpFetcher] over `dart:io`.
class IoHttpFetcher implements HttpFetcher {
  IoHttpFetcher({
    HttpClient? client,
    this.userAgent = 'Rubisco',
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final String userAgent;

  /// How long to wait for a response to start and between chunks of body.
  final Duration timeout;

  @override
  Future<Object?> getJson(Uri url) async {
    final bytes = await getBytes(url, maxBytes: 8 * 1024 * 1024);
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw FetchException('$url did not return valid JSON: ${error.message}');
    }
  }

  @override
  Future<Uint8List> getBytes(
    Uri url, {
    required int maxBytes,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (url.scheme != 'https') {
      throw FetchException('Refusing to fetch $url over ${url.scheme}');
    }

    try {
      final request = await _client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close().timeout(timeout);

      // A redirect must not downgrade the connection. The client follows
      // them on its own, so check where it ended up.
      for (final redirect in response.redirects) {
        if (redirect.location.scheme != 'https') {
          await response.drain<void>();
          throw FetchException('Refused a redirect to ${redirect.location}');
        }
      }

      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw FetchException(
          '$url returned HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final total = response.contentLength >= 0 ? response.contentLength : null;
      if (total != null && total > maxBytes) {
        await response.drain<void>();
        throw FetchException('$url is larger than the $maxBytes-byte limit');
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw FetchException('$url is larger than the $maxBytes-byte limit');
        }
        onProgress?.call(builder.length, total);
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw FetchException('Timed out fetching $url');
    } on SocketException catch (error) {
      throw FetchException('Could not reach ${url.host}: ${error.message}');
    } on HandshakeException catch (error) {
      throw FetchException(
        'TLS failure talking to ${url.host}: ${error.message}',
      );
    } on HttpException catch (error) {
      throw FetchException('HTTP error fetching $url: ${error.message}');
    }
  }

  void close() => _client.close(force: true);
}
