import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
