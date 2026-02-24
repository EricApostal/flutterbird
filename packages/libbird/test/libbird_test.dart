import 'package:flutter_test/flutter_test.dart';
import 'package:libbird/libbird.dart';
import 'package:libbird/libbird_platform_interface.dart';
import 'package:libbird/libbird_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockLibbirdPlatform
    with MockPlatformInterfaceMixin
    implements LibbirdPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final LibbirdPlatform initialPlatform = LibbirdPlatform.instance;

  test('$MethodChannelLibbird is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelLibbird>());
  });

  test('getPlatformVersion', () async {
    Libbird libbirdPlugin = Libbird();
    MockLibbirdPlatform fakePlatform = MockLibbirdPlatform();
    LibbirdPlatform.instance = fakePlatform;

    expect(await libbirdPlugin.getPlatformVersion(), '42');
  });
}
