import Cocoa
import FlutterMacOS
import desktop_multi_window
import url_launcher_macos
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    // The Flutter view over the window's vibrancy, which shows through only in the macOS Tahoe look
    // (lib/desktop/backdrop.dart): Flutter's own background is clear, and the app paints the
    // window opaque in its other looks.
    flutterViewController.backgroundColor = NSColor.clear
    self.contentViewController = GlassController(flutter: flutterViewController)
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The app's own channel (lib/desktop/desktop.dart): links and Dock items.
    let channel = FlutterMethodChannel(
      name: "org.uwuapps.fixup/desktop", binaryMessenger: flutterViewController.engine.binaryMessenger)
    AppDelegate.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setBackdrop", let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      var arguments: [String: Any] = [:]
      if let argumentMap = call.arguments as? [String: Any] {
        arguments = argumentMap
      }
      var on = false
      if let onValue = arguments["on"] as? Bool {
        on = onValue
      }
      var dark = false
      if let darkValue = arguments["dark"] as? Bool {
        dark = darkValue
      }
      result(self.setBackdrop(on: on, dark: dark))
    }
    if !AppDelegate.pendingLinks.isEmpty {
      let links = AppDelegate.pendingLinks
      AppDelegate.pendingLinks = []
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

  /// The desktop through the window, blurred (NSVisualEffectView's behind-window vibrancy, which
  /// macOS Tahoe draws as its glass), light or dark as the app is rather than as the system is.
  func setBackdrop(on: Bool, dark: Bool) -> Bool {
    guard let glass = contentViewController as? GlassController else {
      return false
    }
    glass.effect.isHidden = !on
    isOpaque = !on
    if on {
      backgroundColor = NSColor.clear
      if dark {
        appearance = NSAppearance(named: .darkAqua)
      } else {
        appearance = NSAppearance(named: .aqua)
      }
    } else {
      backgroundColor = NSColor.windowBackgroundColor
      appearance = nil
    }
    invalidateShadow()
    return on
  }

  // Hidden until the Dart side has drawn and sized it (window_manager).
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWindow: Int) {
    super.order(place, relativeTo: otherWindow)
    hiddenWindowAtLaunch()
  }
}

/// The window's content: the vibrancy view behind (hidden until asked for), the Flutter view over it.
class GlassController: NSViewController {
  let flutter: FlutterViewController
  let effect = NSVisualEffectView()

  init(flutter: FlutterViewController) {
    self.flutter = flutter
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    effect.frame = root.bounds
    effect.autoresizingMask = [.width, .height]
    effect.blendingMode = .behindWindow
    effect.material = .sidebar
    effect.state = .followsWindowActiveState
    effect.isHidden = true
    root.addSubview(effect)
    addChild(flutter)
    flutter.view.frame = root.bounds
    flutter.view.autoresizingMask = [.width, .height]
    root.addSubview(flutter.view)
    view = root
  }
}
