import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'libbird_platform_interface.dart';

/// An implementation of [LibbirdPlatform] that uses method channels.
class MethodChannelLibbird extends LibbirdPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('libbird');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
