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
        // Position directly above desktop wallpaper level (-2147483623) and safely below desktop icons (-2147483603)
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        // Allow screen recordings, screenshots, and screen shares to capture the live desktop canvas
        panel.sharingType = .readOnly
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
    }

    @MainActor
    public func updateFrame(for screen: NSScreen) {
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: true)
        }
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
        panel.orderFront(nil)
        panel.setIsVisible(true)
    }

    @MainActor
    public func dismiss() {
        panel.setIsVisible(false)
        panel.orderOut(nil)
    }
}
