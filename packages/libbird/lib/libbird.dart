import 'libbird_platform_interface.dart';
export 'native_view.dart';

class Libbird {
  Future<String?> getPlatformVersion() {
    return LibbirdPlatform.instance.getPlatformVersion();
  }
}
