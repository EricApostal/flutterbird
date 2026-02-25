import Cocoa
import FlutterMacOS

public class LibbirdPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "libbird", binaryMessenger: registrar.messenger)
    let instance = LibbirdPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
      
  let factory = NativeViewFactory(messenger: registrar.messenger)
  registrar.register(factory, withId: "hosted_platform_view")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

