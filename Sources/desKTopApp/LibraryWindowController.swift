import AppKit
import SwiftUI
import desKTopCore

/// Auxiliary management window controller for background menu-bar accessory
@MainActor
public final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = LibraryWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "desKTop — Tezos Art Gallery"
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

        let hosting = NSHostingView(rootView: LibraryView(repository: repository, onSetWallpaper: onSetWallpaper))
        window.contentView = hosting

        // Switch to .regular activation policy so the Dock icon appears while the window is open
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        // Return strictly to .accessory policy when window is closed (Dock icon disappears)
        NSApp.setActivationPolicy(.accessory)
    }
}
