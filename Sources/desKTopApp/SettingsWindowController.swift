import AppKit
import SwiftUI
import desKTopCore

@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "desKTop Settings"
        window.center()
        window.setFrameAutosaveName("desKTopSettingsWindowAutosave")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(repository: WalletRepository) {
        guard let window = self.window else { return }

        if let iconImage = Bundle.main.image(forResource: "AppIcon") ??
                           NSImage(contentsOfFile: "/Users/joepeterson/development/desKTop/app/Resources/AppIcon.icns") {
            NSApp.applicationIconImage = iconImage
        }

        let hosting = NSHostingView(rootView: SettingsView(repository: repository))
        window.contentView = hosting

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        // Return to .accessory policy if Library window is not open
        if NSApp.windows.allSatisfy({ !$0.isVisible || $0.level == NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow))) }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
