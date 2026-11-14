// uwuFix for macOS: the runner (docs/flutter-desktop-app-spec.md §2.7).
//
// - Keeps running with no window, in the menu bar (lib/desktop/tray.dart); clicking the Dock icon
//   brings the window back.
// - uwu://fix links (Info.plist's URL types) go to the Dart side's channel as "open".
// - The Dock's menu: Fix copied link, History, Share history, Add a Fix a link widget, each a
//   "task" for the Dart side.
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var channel: FlutterMethodChannel?
  // Links that came before the Dart side was listening.
  static var pending: [String] = []

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    AppDelegate.channel?.invokeMethod("activate", arguments: nil)
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    let links = urls.map { $0.absoluteString }
    if let channel = AppDelegate.channel {
      channel.invokeMethod("open", arguments: links)
    } else {
      AppDelegate.pending.append(contentsOf: links)
    }
  }

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()
    for (title, task) in [
      ("Fix copied link", "paste"),
      ("History", "history"),
      ("Share history", "sync"),
      ("Add a Fix a link widget", "widget"),
    ] {
      let item = NSMenuItem(title: title, action: #selector(dockTask(_:)), keyEquivalent: "")
      item.representedObject = task
      item.target = self
      menu.addItem(item)
    }
    return menu
  }

  @objc func dockTask(_ sender: NSMenuItem) {
    AppDelegate.channel?.invokeMethod("task", arguments: sender.representedObject as? String)
  }
}
