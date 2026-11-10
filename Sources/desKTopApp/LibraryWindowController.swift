import AppKit
import SwiftUI
import desKTopCore

/// Auxiliary management window controller for background menu-bar accessory
@MainActor
public final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = LibraryWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "desKTop — Tezos Art Gallery"
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.setFrameAutosaveName("desKTopLibraryWindowAutosave")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(repository: WalletRepository, onSetWallpaper: @escaping (UnifiedToken) -> Void) {
        guard let window = self.window else { return }

        // Ensure the Dock icon uses the branded AppIcon
        if let iconImage = Bundle.main.image(forResource: "AppIcon") ??
                           NSImage(contentsOfFile: "/Users/joepeterson/development/desKTop/app/Resources/AppIcon.icns") {
            NSApp.applicationIconImage = iconImage
        }

        if window.contentView is NSHostingView<LibraryView> {
            NotificationCenter.default.post(name: Notification.Name("didReopenLibraryWindow"), object: nil)
        } else {
            let hosting = NSHostingView(rootView: LibraryView(repository: repository, onSetWallpaper: onSetWallpaper))
            window.contentView = hosting
        }

        // Switch to .regular activation policy so the Dock icon appears while the window is open
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        // Return to .accessory policy when window is closed, unless Settings window is still open
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
