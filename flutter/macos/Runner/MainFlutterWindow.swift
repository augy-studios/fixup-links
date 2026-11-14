import Cocoa
import FlutterMacOS
import desktop_multi_window
import url_launcher_macos
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The app's own channel (lib/desktop/desktop.dart): links and Dock items.
    let channel = FlutterMethodChannel(
      name: "org.uwuapps.fixup/desktop", binaryMessenger: flutterViewController.engine.binaryMessenger)
    AppDelegate.channel = channel
    if !AppDelegate.pending.isEmpty {
      let links = AppDelegate.pending
      AppDelegate.pending = []
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        channel.invokeMethod("open", arguments: links)
      }
    }

    // The Fix a link widgets' windows (lib/desktop/widgets_window.dart) are engines of their own,
    // which need the plugins they use registered too.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      WindowManagerPlugin.register(with: controller.registrar(forPlugin: "WindowManagerPlugin"))
      UrlLauncherPlugin.register(with: controller.registrar(forPlugin: "UrlLauncherPlugin"))
    }

    super.awakeFromNib()
  }

  // Hidden until the Dart side has drawn and sized it (window_manager).
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
