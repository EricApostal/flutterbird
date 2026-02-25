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
        wrapper.loadURL("https://ladybird.org")
        return wrapper.getView()
    }
}
