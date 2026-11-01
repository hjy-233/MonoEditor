import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var explorerMenuChannel: FlutterMethodChannel?
  private var selectedExplorerAction: String?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)
    styleMask.insert(.fullSizeContentView)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupExplorerMenu(flutterViewController)

    super.awakeFromNib()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(centerWindowButtons),
      name: NSWindow.didResizeNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(centerWindowButtons),
      name: NSWindow.didExitFullScreenNotification,
      object: self
    )
    DispatchQueue.main.async { [weak self] in
      self?.centerWindowButtons()
    }
  }

  private func setupExplorerMenu(_ flutterViewController: FlutterViewController) {
    let menuChannel = FlutterMethodChannel(
      name: "org.dcstudio.MonoEditor/explorerMenu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    menuChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "show", let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let action = self.showExplorerMenu(canUndo: arguments?["canUndo"] as? Bool ?? false)
      DispatchQueue.main.async {
        self.makeKeyAndOrderFront(nil)
        result(action)
      }
    }
    explorerMenuChannel = menuChannel
  }

  private func showExplorerMenu(canUndo: Bool) -> String? {
    guard let contentView else { return nil }
    let menu = NSMenu()
    for (title, action) in [("重命名", "rename"), ("删除…", "delete")] {
      let item = NSMenuItem(title: title, action: #selector(selectExplorerMenuItem(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action
      menu.addItem(item)
    }
    if canUndo {
      menu.addItem(.separator())
      let item = NSMenuItem(
        title: "撤销上次文件操作",
        action: #selector(selectExplorerMenuItem(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = "undo"
      menu.addItem(item)
    }
    selectedExplorerAction = nil
    let point = contentView.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    menu.popUp(positioning: nil, at: point, in: contentView)
    return selectedExplorerAction
  }

  @objc private func selectExplorerMenuItem(_ item: NSMenuItem) {
    selectedExplorerAction = item.representedObject as? String
  }

  @objc private func centerWindowButtons() {
    guard !styleMask.contains(.fullScreen), let contentView else { return }
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      guard let button = standardWindowButton(type), let container = button.superview else {
        continue
      }
      let center = contentView.convert(
        NSPoint(x: 0, y: contentView.bounds.maxY - 23),
        to: container
      )
      button.frame.origin.y = center.y - button.frame.height / 2
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
