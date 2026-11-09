import SwiftUI
import AppKit
import desKTopCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var currentToken: UnifiedToken?
    @Published var isPaused: Bool = false
    @Published var scaling: WallpaperScaling = .fit
    @Published var statusMessage: String = "Active"
}

struct MenuBarPopoverWrapperView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onRestartAnimation: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        MenuBarContentView(
            currentToken: $viewModel.currentToken,
            isPaused: $viewModel.isPaused,
            scaling: $viewModel.scaling,
            statusMessage: viewModel.statusMessage,
            onNext: onNext,
            onPrevious: onPrevious,
            onRestartAnimation: onRestartAnimation,
            onOpenLibrary: onOpenLibrary
        )
        .padding(14)
        .frame(width: 320)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = MenuBarViewModel()

    private let repository = WalletRepository()
    private let wallpaperService = StillWallpaperService()
    private let vault = MediaVault()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Strictly start with .accessory policy: zero presence in Dock or Cmd+Tab
        NSApp.setActivationPolicy(.accessory)

        // Preload branded icon for when window is opened
        if let iconImage = Bundle.main.image(forResource: "AppIcon") ??
                           NSImage(contentsOfFile: "/Users/joepeterson/development/desKTop/app/Resources/AppIcon.icns") {
            NSApp.applicationIconImage = iconImage
        }

        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppBranding.dynamicMenuBarIcon
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 260)
        popover.behavior = .transient
        popover.delegate = self

        let contentView = MenuBarPopoverWrapperView(
            viewModel: viewModel,
            onNext: { [weak self] in
                Task { await self?.rotateNext() }
            },
            onPrevious: { [weak self] in
                Task { await self?.rotatePrevious() }
            },
            onRestartAnimation: {},
            onOpenLibrary: { [weak self] in
                self?.openLibraryWindow()
            }
        )

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        }

        let menu = NSMenu(title: "desKTop")

        let openItem = NSMenuItem(title: "Open Gallery Window…", action: #selector(openLibraryWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let infoItem = NSMenuItem(title: "About desKTop…", action: #selector(showAboutDialog), keyEquivalent: "i")
        infoItem.target = self
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit desKTop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openLibraryWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        LibraryWindowController.shared.show(repository: repository) { [weak self] token in
            Task {
                await self?.setTokenAsWallpaper(token)
            }
        }
    }

    @objc private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "desKTop"
        alert.informativeText = "Version 1.0.0\n\nA clean-room native macOS desktop wallpaper manager for Tezos art NFTs.\n\nCreated by FAFOlab (a FAFOlab joint)\nhttps://fafolab.xyz\n\nReleased under The Unlicense."
        alert.alertStyle = .informational
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Visit FAFOlab")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://fafolab.xyz") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func setTokenAsWallpaper(_ token: UnifiedToken) async {
        guard let uri = token.primaryWallpaperUri else {
            viewModel.statusMessage = "No media available"
            return
        }

        viewModel.statusMessage = "Rendering \(token.name)..."
        do {
            let (fileURL, _) = try await vault.getOrFetchMedia(for: uri)
            if let screen = NSScreen.main {
                do {
                    _ = try wallpaperService.setDesktopWallpaper(
                        imageURL: fileURL,
                        tokenId: token.tokenId,
                        for: screen,
                        scaling: viewModel.scaling
                    )
                    self.viewModel.currentToken = token
                    self.viewModel.statusMessage = "Live on \(screen.localizedName)"
                } catch {
                    self.viewModel.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        } catch {
            self.viewModel.statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    private func rotateNext() async {
        let tokens = await repository.getTokens()
        guard !tokens.isEmpty else { return }

        if let current = viewModel.currentToken,
           let idx = tokens.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = (idx + 1) % tokens.count
            await setTokenAsWallpaper(tokens[nextIdx])
        } else if let first = tokens.first {
            await setTokenAsWallpaper(first)
        }
    }

    private func rotatePrevious() async {
        let tokens = await repository.getTokens()
        guard !tokens.isEmpty else { return }

        if let current = viewModel.currentToken,
           let idx = tokens.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + tokens.count) % tokens.count
            await setTokenAsWallpaper(tokens[prevIdx])
        } else if let last = tokens.last {
            await setTokenAsWallpaper(last)
        }
    }
}

@main
struct desKTopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
