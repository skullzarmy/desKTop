import AppKit
import SwiftUI
import desKTopCore

/// Auxiliary management window controller for background menu-bar accessory
@MainActor
public final class LibraryWindowController: NSWindowController {
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(repository: WalletRepository, onSetWallpaper: @escaping (UnifiedToken) -> Void) {
        guard let window = self.window else { return }

        let hosting = NSHostingView(rootView: LibraryView(repository: repository, onSetWallpaper: onSetWallpaper))
        window.contentView = hosting

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
