import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  var shareChannel: FlutterMethodChannel?
  var pendingShare: [String:String]?
  var receiverReady = false
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    return true
  }
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard url.scheme == "kodoukoly", url.host == "share",
            let parts=URLComponents(url:url,resolvingAgainstBaseURL:false),
            let text=parts.queryItems?.first(where:{$0.name=="text"})?.value,
            !text.isEmpty, text.utf8.count <= 60000 else { continue }
      let title=parts.queryItems?.first(where:{$0.name=="title"})?.value ?? ""
      let payload=["text":text,"title":String(title.prefix(200))]
      if receiverReady { shareChannel?.invokeMethod("share",arguments:payload) }
      else { pendingShare=payload }
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps:true)
    }
  }
}
