import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    if let delegate=NSApp.delegate as? AppDelegate {
      let channel=FlutterMethodChannel(name:"cz.kodo.ukoly/share",binaryMessenger:flutterViewController.engine.binaryMessenger)
      delegate.shareChannel=channel
      channel.setMethodCallHandler { call,result in
        if call.method == "takePending" {
          delegate.receiverReady=true
          result(delegate.pendingShare);delegate.pendingShare=nil
        } else if call.method == "pauseReceiver" { delegate.receiverReady=false;result(nil) } else { result(FlutterMethodNotImplemented) }
      }
    }
    super.awakeFromNib()
  }
}
