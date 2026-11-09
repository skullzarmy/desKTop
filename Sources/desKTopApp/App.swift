import SwiftUI
import AppKit
import desKTopCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Strictly set activation policy to accessory so it NEVER appears in the macOS Dock
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct desKTopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var currentToken: UnifiedToken?
    @State private var isPaused: Bool = false
    @State private var scaling: WallpaperScaling = .fit
    @State private var statusMessage: String = "Active"

    private let repository = WalletRepository()
    private let wallpaperService = StillWallpaperService()
    private let vault = MediaVault()

    private var menuBarIcon: NSImage? {
        // 1. Try Bundle resource
        if let bundleURL = Bundle.main.url(forResource: "menu_bar_icon@2x", withExtension: "png", subdirectory: "Resources/Branding") ??
                           Bundle.main.url(forResource: "menu_bar_icon@2x", withExtension: "png") ??
                           Bundle.main.url(forResource: "menu_bar_icon", withExtension: "png") {
            if let img = NSImage(contentsOf: bundleURL) {
                img.size = NSSize(width: 18, height: 18)
                return img
            }
        }

        // 2. Fallback direct path
        let directPath = "/Users/joepeterson/development/desKTop/app/Resources/Branding/menu_bar_icon@2x.png"
        if let img = NSImage(contentsOfFile: directPath) {
            img.size = NSSize(width: 18, height: 18)
            return img
        }

        return nil
    }

    var body: some Scene {
        // Pure MenuBarExtra - no dock icon, no unwanted launch window
        MenuBarExtra {
            MenuBarContentView(
                currentToken: $currentToken,
                isPaused: $isPaused,
                scaling: $scaling,
                statusMessage: statusMessage,
                onNext: {
                    Task { await rotateNext() }
                },
                onPrevious: {
                    Task { await rotatePrevious() }
                },
                onRestartAnimation: {},
                onOpenLibrary: {
                    LibraryWindowController.shared.show(repository: repository) { token in
                        Task {
                            await setTokenAsWallpaper(token)
                        }
                    }
                }
            )
        } label: {
            if let icon = menuBarIcon {
                Image(nsImage: icon)
            } else {
                Text("desKTop")
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func setTokenAsWallpaper(_ token: UnifiedToken) async {
        guard let uri = token.primaryWallpaperUri else {
            statusMessage = "No media available"
            return
        }

        statusMessage = "Rendering \(token.name)..."
        do {
            let (fileURL, _) = try await vault.getOrFetchMedia(for: uri)
            await MainActor.run {
                if let screen = NSScreen.main {
                    do {
                        _ = try wallpaperService.setDesktopWallpaper(
                            imageURL: fileURL,
                            tokenId: token.tokenId,
                            for: screen,
                            scaling: scaling
                        )
                        self.currentToken = token
                        self.statusMessage = "Live on \(screen.localizedName)"
                    } catch {
                        self.statusMessage = "Error: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.statusMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func rotateNext() async {
        let tokens = await repository.getTokens()
        guard !tokens.isEmpty else { return }

        if let current = currentToken,
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

        if let current = currentToken,
           let idx = tokens.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + tokens.count) % tokens.count
            await setTokenAsWallpaper(tokens[prevIdx])
        } else if let last = tokens.last {
            await setTokenAsWallpaper(last)
        }
    }
}
