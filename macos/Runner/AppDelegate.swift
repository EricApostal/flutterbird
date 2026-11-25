import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The engine runs with no window of its own: every browser window is made by
  // Dart with Flutter's windowing API, which needs the engine never to have had
  // a view that was not made that way. So there is no window in MainMenu.xib
  // either, and no window is more the app than another.
  private var engine: FlutterEngine?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let engine = FlutterEngine(name: "flutterbird", project: nil)
    RegisterGeneratedPlugins(registry: engine)
    engine.run(withEntrypoint: nil)
    self.engine = engine
  }

  // Dart quits the app when its last window closes. AppKit deciding that itself
  // would quit in the moment where a window being replaced has gone and the one
  // replacing it has yet to draw, and so is not yet on screen.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
