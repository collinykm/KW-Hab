import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var shellChannel: FlutterMethodChannel?
  private let menuTarget = ShellMenuTarget()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Desktop-sized default window, centered, with a sensible minimum size.
    self.title = "Facebook"
    self.minSize = NSSize(width: 900, height: 600)
    self.setContentSize(NSSize(width: 1400, height: 900))
    self.center()
    self.setFrameAutosaveName("FacebookMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "kw_hab/shell",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setTitle":
        if let title = call.arguments as? String, !title.isEmpty {
          self?.title = title
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    shellChannel = channel
    menuTarget.channel = channel
    installBrowserMenuItems()

    super.awakeFromNib()
  }

  /// Adds browser-style commands (reload, back/forward, zoom) to the native
  /// menu bar so the standard macOS shortcuts work while the web view has focus.
  private func installBrowserMenuItems() {
    guard let mainMenu = NSApp.mainMenu else { return }

    // Navigation lives in its own "History" menu, like Safari.
    let historyMenu = NSMenu(title: "History")
    historyMenu.addItem(menuItem("Back", "back", key: "["))
    historyMenu.addItem(menuItem("Forward", "forward", key: "]"))
    historyMenu.addItem(.separator())
    historyMenu.addItem(menuItem("Home", "home", key: "h", modifiers: [.command, .shift]))
    let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
    historyItem.submenu = historyMenu

    if let viewItem = mainMenu.items.first(where: { $0.title == "View" }),
       let viewMenu = viewItem.submenu {
      let additions: [NSMenuItem] = [
        menuItem("Reload Page", "reload", key: "r"),
        .separator(),
        menuItem("Actual Size", "zoomReset", key: "0"),
        menuItem("Zoom In", "zoomIn", key: "="),
        menuItem("Zoom Out", "zoomOut", key: "-"),
        .separator(),
      ]
      for (index, item) in additions.enumerated() {
        viewMenu.insertItem(item, at: index)
      }
      let viewIndex = mainMenu.index(of: viewItem)
      mainMenu.insertItem(historyItem, at: viewIndex + 1)
    } else {
      mainMenu.addItem(historyItem)
    }
  }

  private func menuItem(
    _ title: String, _ command: String, key: String,
    modifiers: NSEvent.ModifierFlags = [.command]
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: title, action: #selector(ShellMenuTarget.perform(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.representedObject = command
    item.target = menuTarget
    return item
  }
}

/// Forwards native menu selections to Dart over the shell channel.
class ShellMenuTarget: NSObject {
  weak var channel: FlutterMethodChannel?

  @objc func perform(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    channel?.invokeMethod("menu", arguments: command)
  }
}
