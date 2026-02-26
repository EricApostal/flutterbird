import Cocoa
import FlutterMacOS

public class LibbirdPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    LadybirdEngine.initializeEngine()

    let instance = LibbirdPlugin()
    
    let channel = FlutterMethodChannel(name: "libbird", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
    
    let factory = LadybirdViewFactory(messenger: registrar.messenger)
    registrar.register(factory, withId: "ladybird_view")
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

class LadybirdViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        // Just return directly
        return LadybirdEngine.createWebView(withFrame: .zero)
    }
}
