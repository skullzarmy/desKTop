import AppKit
import Foundation

/// Borderless desktop canvas panel sitting directly at kCGDesktopWindowLevel behind desktop icons
public final class DesktopCanvasWindowController: NSWindowController {
    public let displayUUID: String
    private let panel: NSPanel

    @MainActor
    public init(screen: NSScreen, displayUUID: String) {
        self.displayUUID = displayUUID

        let frame = screen.frame
        self.panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: self.panel)

        setupPanelProperties(screen: screen)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    private func setupPanelProperties(screen: NSScreen) {
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        panel.sharingType = .none
        panel.hasShadow = false
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false

        // Maintain persistence across Spaces and Mission Control
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenNone
        ]

        panel.setFrame(screen.frame, display: true)
        panel.orderBack(nil)
    }

    @MainActor
    public func setCanvasContent(_ view: NSView) {
        view.frame = panel.contentView?.bounds ?? panel.frame
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
    }

    @MainActor
    public func setBackgroundColor(_ color: NSColor) {
        panel.backgroundColor = color
    }

    @MainActor
    public func present() {
        panel.orderBack(nil)
        panel.setIsVisible(true)
    }

    @MainActor
    public func dismiss() {
        panel.setIsVisible(false)
        panel.orderOut(nil)
    }
}
