import 'dart:async';
import 'dart:convert';

import 'package:bird_devtools/src/protocol/rdp_client.dart';
import 'package:bird_devtools/src/protocol/rdp_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server end that records what it is sent and says what it is told to.
class FakeChannel implements RdpChannel {
  final StreamController<RdpPacket> incoming = StreamController<RdpPacket>(sync: true);
  final List<RdpPacket> sent = [];

  @override
  Stream<RdpPacket> get packets => incoming.stream;

  @override
  void send(RdpPacket packet) => sent.add(packet);

  void say(RdpPacket packet) => incoming.add(packet);

  @override
  Future<void> close() async {
    if (!incoming.isClosed) unawaited(incoming.close());
  }
}

void main() {
  group('framing', () {
    test('counts bytes, not characters', () {
      final bytes = encodeRdpPacket({'to': 'root', 'value': 'héllo ☃'});
      final text = utf8.decode(bytes);
      final colon = text.indexOf(':');
      expect(int.parse(text.substring(0, colon)), utf8.encode(text.substring(colon + 1)).length);
    });

    test('survives any way of cutting up the stream', () {
      final packets = [
        {'from': 'a', 'n': 1},
        {'from': 'b', 'text': 'x: y ☃' * 3000},
        {'from': 'c'},
      ];
      final stream = [for (final packet in packets) ...encodeRdpPacket(packet)];
      for (final size in [1, 2, 7, 100, 4096, stream.length]) {
        final decoder = RdpPacketDecoder();
        final read = <RdpPacket>[];
        for (var at = 0; at < stream.length; at += size) {
          read.addAll(decoder.add(stream.sublist(at, (at + size).clamp(0, stream.length))));
        }
        expect(read, packets, reason: 'chunks of $size');
      }
    });

    test('rejects what is not the protocol', () {
      expect(() => RdpPacketDecoder().add(utf8.encode('nope:{}')), throwsFormatException);
      expect(() => RdpPacketDecoder().add(utf8.encode('HTTP/1.1 200 OK and more text')), throwsFormatException);
      expect(() => RdpPacketDecoder().add(utf8.encode('999999999999:')), throwsFormatException);
    });
  });

  group('client', () {
    late FakeChannel channel;
    late RdpClient client;

    setUp(() {
      channel = FakeChannel();
      client = RdpClient(channel);
    });

    test('answers go to requests in the order they were asked', () async {
      final first = client.request('actor', 'one');
      final second = client.request('actor', 'two');
      channel.say({'from': 'actor', 'value': 1});
      channel.say({'from': 'actor', 'value': 2});
      expect((await first)['value'], 1);
      expect((await second)['value'], 2);
    });

    test('events do not answer requests', () async {
      final events = <RdpPacket>[];
      client.events.listen(events.add);
      final request = client.request('console', 'evaluateJSAsync');
      channel.say({'from': 'console', 'type': 'evaluationResult', 'resultID': 'x'});
      channel.say({'from': 'console', 'resultID': 'x'});
      expect((await request).containsKey('type'), isFalse);
      expect(events.single['type'], 'evaluationResult');
    });

    test('a debugger environment, which has a type, is still an answer', () async {
      final request = client.request('frame', 'getEnvironment');
      channel.say({'from': 'frame', 'type': 'function', 'bindings': <String, Object?>{}});
      expect((await request)['type'], 'function');
    });

    test('the root actor answers for actors that are gone', () async {
      final gone = client.request('server0-netEvent3', 'getResponseHeaders');
      final root = client.request('root', 'listTabs');
      channel.say({'from': 'root', 'error': 'unknownActor', 'message': "Unknown actor: 'server0-netEvent3'"});
      channel.say({'from': 'root', 'tabs': <Object?>[]});
      await expectLater(gone, throwsA(isA<RdpError>().having((e) => e.isUnknownActor, 'unknown', isTrue)));
      expect((await root)['tabs'], isEmpty);
    });

    test('a late answer is not taken for the next one', () async {
      final slow = client.request('a', 'slow', const {}, const Duration(milliseconds: 20));
      await expectLater(slow, throwsA(isA<RdpError>().having((e) => e.isTimeout, 'timeout', isTrue)));
      final next = client.request('a', 'next');
      channel.say({'from': 'a', 'which': 'slow'});
      channel.say({'from': 'a', 'which': 'next'});
      expect((await next)['which'], 'next');
    });

    test('closing fails what is waiting', () async {
      final waiting = client.request('a', 'b');
      final expectation = expectLater(waiting, throwsA(isA<RdpError>().having((e) => e.isClosed, 'closed', isTrue)));
      await client.close();
      await expectation;
      await expectLater(client.request('a', 'c'), throwsA(isA<RdpError>()));
    });
  });
}
