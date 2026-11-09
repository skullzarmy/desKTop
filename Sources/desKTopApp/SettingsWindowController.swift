import AppKit
import SwiftUI
import desKTopCore

/// Singleton window controller ensuring a single unified Settings window across
/// the MenuBar gear icon, the application menu "desKTop -> Settings...", and Cmd+,
@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var currentRepository: WalletRepository?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
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

        self.currentRepository = repository
        let hosting = NSHostingView(rootView: SettingsView(repository: repository))
        window.contentView = hosting

        // Activate regular policy so the Settings window behaves like a first-class macOS window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        // Return to .accessory policy when window is closed, unless Library window is still open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasVisible = NSApp.windows.contains { w in
                w.isVisible && w.canBecomeKey && w.level == .normal && !(w is NSPanel)
            }
            if !hasVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
