import Cocoa
import FlutterMacOS

public class LibbirdPlugin: NSObject, FlutterPlugin {
  var textureRegistry: FlutterTextureRegistry?
  var timer: Timer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "libbird", binaryMessenger: registrar.messenger)
    let instance = LibbirdPlugin()
    instance.textureRegistry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)

  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
