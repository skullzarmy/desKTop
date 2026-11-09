import SwiftUI
import AppKit
import desKTopCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct desKTopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    @State private var currentToken: UnifiedToken?
    @State private var isPaused: Bool = false
    @State private var scaling: WallpaperScaling = .fit
    @State private var statusMessage: String = "Ready"

    private let repository = WalletRepository()
    private let wallpaperService = StillWallpaperService()
    private let vault = MediaVault()

    var body: some Scene {
        // 1. Menu Bar Companion
        MenuBarExtra("desKTop", systemImage: "photo.artframe") {
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
                onRestartAnimation: {
                    // Replay trigger
                },
                onOpenLibrary: {
                    openWindow(id: "library-window")
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
        }
        .menuBarExtraStyle(.window)

        // 2. Main Desktop Management Window
        Window("desKTop — Tezos Art Gallery", id: "library-window") {
            LibraryView(repository: repository) { token in
                Task {
                    await setTokenAsWallpaper(token)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1080, height: 720)
    }

    private func setTokenAsWallpaper(_ token: UnifiedToken) async {
        guard let uri = token.primaryWallpaperUri else {
            statusMessage = "No visual media available"
            return
        }

        statusMessage = "Caching & rendering \(token.name)..."
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
                        self.statusMessage = "Active on \(screen.localizedName)"
                    } catch {
                        self.statusMessage = "Failed setting wallpaper: \(error.localizedDescription)"
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
