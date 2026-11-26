import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One JSON packet of the Mozilla remote debugging protocol.
typedef RdpPacket = Map<String, Object?>;

/// Frames [packet] as `length:JSON`, the length counting UTF-8 bytes.
List<int> encodeRdpPacket(RdpPacket packet) {
  final body = utf8.encode(jsonEncode(packet));
  final head = ascii.encode('${body.length}:');
  return Uint8List(head.length + body.length)
    ..setRange(0, head.length, head)
    ..setRange(head.length, head.length + body.length, body);
}

/// Splits the protocol's byte stream back into packets, however it is chunked.
class RdpPacketDecoder {
  /// No honest packet is larger. A stream that says so is not speaking the
  /// protocol, and is not worth buffering.
  static const int maxPacketBytes = 256 * 1024 * 1024;

  Uint8List _buffer = Uint8List(4096);
  int _start = 0;
  int _end = 0;

  // The length of the packet being read, once its header is in.
  int? _bodyLength;

  /// Takes the next bytes off the wire and returns the packets they complete.
  /// Throws a [FormatException] if the stream is not the protocol.
  List<RdpPacket> add(List<int> chunk) {
    _append(chunk);
    final packets = <RdpPacket>[];
    while (true) {
      var length = _bodyLength;
      if (length == null) {
        final colon = _indexOfColon();
        if (colon < 0) {
          if (_end - _start > 20) {
            throw const FormatException('Packet header has no length');
          }
          break;
        }
        length = int.tryParse(
          ascii.decode(_buffer.sublist(_start, colon), allowInvalid: true),
        );
        if (length == null || length < 0 || length > maxPacketBytes) {
          throw const FormatException('Bad packet length');
        }
        _bodyLength = length;
        _start = colon + 1;
      }
      if (_end - _start < length) break;
      final body = Uint8List.sublistView(_buffer, _start, _start + length);
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: true));
      _start += length;
      _bodyLength = null;
      if (decoded is Map<String, Object?>) packets.add(decoded);
    }
    if (_start == _end) _start = _end = 0;
    return packets;
  }

  int _indexOfColon() {
    for (var i = _start; i < _end; i++) {
      if (_buffer[i] == 0x3A) return i;
    }
    return -1;
  }

  void _append(List<int> chunk) {
    final used = _end - _start;
    if (_end + chunk.length > _buffer.length) {
      var capacity = _buffer.length;
      while (used + chunk.length > capacity) {
        capacity *= 2;
      }
      // Doubling keeps a packet of many chunks from being copied once a chunk.
      final grown = capacity == _buffer.length ? _buffer : Uint8List(capacity);
      grown.setRange(0, used, _buffer, _start);
      _buffer = grown;
      _start = 0;
      _end = used;
    }
    _buffer.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }
}

/// A connection that carries packets both ways.
abstract class RdpChannel {
  Stream<RdpPacket> get packets;
  void send(RdpPacket packet);
  Future<void> close();
}

/// The protocol over a TCP socket.
class RdpSocketChannel implements RdpChannel {
  RdpSocketChannel._(this._socket) {
    final decoder = RdpPacketDecoder();
    _socket.listen(
      (chunk) {
        try {
          decoder.add(chunk).forEach(_packets.add);
        } on FormatException catch (error) {
          _packets.addError(error);
          close();
        }
      },
      onError: (Object error) {
        if (!_packets.isClosed) _packets.addError(error);
        close();
      },
      onDone: close,
    );
    // A write to a socket the other end has closed fails here, not at add.
    unawaited(_socket.done.then((_) {}, onError: (Object _) => close()));
  }

  static Future<RdpSocketChannel> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return RdpSocketChannel._(socket);
  }

  final Socket _socket;
  final StreamController<RdpPacket> _packets = StreamController<RdpPacket>();
  bool _closed = false;

  @override
  Stream<RdpPacket> get packets => _packets.stream;

  @override
  void send(RdpPacket packet) {
    if (!_closed) _socket.add(encodeRdpPacket(packet));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    unawaited(_packets.close());
  }
}
