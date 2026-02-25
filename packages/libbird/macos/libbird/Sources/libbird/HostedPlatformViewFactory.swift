import FlutterMacOS
import Foundation

class HostedPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        let wrapper = LadybirdViewWrapper()
        if let argsDict = args as? [String: Any], let url = argsDict["url"] as? String {
            wrapper.loadURL(url)
        } else {
            wrapper.loadURL("https://ladybird.org")
        }
        return wrapper.getView()
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
