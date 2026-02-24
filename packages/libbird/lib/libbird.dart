
import 'libbird_platform_interface.dart';

class Libbird {
  Future<String?> getPlatformVersion() {
    return LibbirdPlatform.instance.getPlatformVersion();
  }
}
