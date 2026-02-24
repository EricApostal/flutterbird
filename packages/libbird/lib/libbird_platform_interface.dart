import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'libbird_method_channel.dart';

abstract class LibbirdPlatform extends PlatformInterface {
  /// Constructs a LibbirdPlatform.
  LibbirdPlatform() : super(token: _token);

  static final Object _token = Object();

  static LibbirdPlatform _instance = MethodChannelLibbird();

  /// The default instance of [LibbirdPlatform] to use.
  ///
  /// Defaults to [MethodChannelLibbird].
  static LibbirdPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LibbirdPlatform] when
  /// they register themselves.
  static set instance(LibbirdPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
