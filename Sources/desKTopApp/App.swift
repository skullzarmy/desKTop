import SwiftUI
import AppKit
import Combine
import ImageIO
import desKTopCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var currentToken: UnifiedToken?
    @Published var isPaused: Bool = false
    @Published var scaling: WallpaperScaling = .fit
    @Published var statusMessage: String = "Active"
    @Published var isFavorite: Bool = false
    @Published var isInteractive: Bool = false
    @Published var isDesktopIconsHidden: Bool = DesktopIconsManager.isDesktopIconsHidden
    @Published var lastHiddenToken: UnifiedToken?
}

struct MenuBarPopoverWrapperView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onRestartAnimation: () -> Void
    let onToggleFavorite: () -> Void
    let onHideToken: () -> Void
    let onUndoLastHide: () -> Void
    let onToggleInteractive: () -> Void
    let onToggleDesktopIcons: () -> Void
    let onEnterGalleryMode: () -> Void
    let onSaveToDownloads: () -> Void
    let onCopyObjktLink: () -> Void
    let onOpenLibrary: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        MenuBarContentView(
            currentToken: $viewModel.currentToken,
            isPaused: $viewModel.isPaused,
            scaling: $viewModel.scaling,
            statusMessage: viewModel.statusMessage,
            isFavorite: viewModel.isFavorite,
            isInteractive: viewModel.isInteractive,
            isDesktopIconsHidden: viewModel.isDesktopIconsHidden,
            lastHiddenTokenName: viewModel.lastHiddenToken?.name,
            onNext: onNext,
            onPrevious: onPrevious,
            onRestartAnimation: onRestartAnimation,
            onToggleFavorite: onToggleFavorite,
            onHideToken: onHideToken,
            onUndoLastHide: onUndoLastHide,
            onToggleInteractive: onToggleInteractive,
            onToggleDesktopIcons: onToggleDesktopIcons,
            onEnterGalleryMode: onEnterGalleryMode,
            onSaveToDownloads: onSaveToDownloads,
            onCopyObjktLink: onCopyObjktLink,
            onOpenLibrary: onOpenLibrary,
            onOpenSettings: onOpenSettings
        )
        .padding(14)
        .frame(width: 330)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = MenuBarViewModel()

    let repository = WalletRepository()
    private let wallpaperService = StillWallpaperService()
    private let vault = MediaVault()
    private var canvasControllers: [String: DesktopCanvasWindowController] = [:]
    private var rotationScheduler: RotationScheduler?
    private var rotationObserver: NSObjectProtocol?
    private var nextWallpaperObserver: NSObjectProtocol?
    private var desktopChangeObserver: NSObjectProtocol?
    private var isRotating: Bool = false
    private var lastAppliedWallpaperURL: URL?
    private var isExternalWallpaperActive: Bool = false
    private var pendingRotationChangeTask: Task<Void, Never>?
    private var applyWallpaperTask: Task<Void, Never>?
    private var wallpaperRequestSeq: UInt64 = 0
    private var lastEvaluatedFreezeState: Bool?
    private var lastAppliedFileURL: URL?
    private var lastAppliedCategory: MediaCategory = .unknown
    private var interactiveEscMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Restore user's preferred framing mode
        if let savedScalingRaw = UserDefaults.standard.string(forKey: "wallpaperScaling"),
           let savedScaling = WallpaperScaling(rawValue: savedScalingRaw) {
            viewModel.scaling = savedScaling
        }

        // React immediately when the user changes Framing mode in the MenuBar UI
        viewModel.$scaling
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newScaling in
                UserDefaults.standard.set(newScaling.rawValue, forKey: "wallpaperScaling")
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let currentToken = self.viewModel.currentToken {
                        await self.setTokenAsWallpaper(currentToken)
                    } else {
                        let tokens = await self.repository.getActiveRotationTokens()
                        if let first = tokens.first {
                            await self.setTokenAsWallpaper(first)
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // React immediately when user pauses / unpauses in MenuBar UI
        viewModel.$isPaused
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] paused in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    try? await self.repository.setRotationPaused(paused)
                    self.rotationScheduler?.isPaused = paused
                    GalleryModeController.shared.updatePauseState(paused)
                    if !paused {
                        await self.syncDesktopState(forceApplyIfExternal: true)
                    }
                }
            }
            .store(in: &cancellables)

        // Listen for space changes or display changes to re-sync state
        desktopChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncDesktopState(forceApplyIfExternal: false)
            }
        }

        // Configure global URLCache with 100 MB memory and 1 GB disk cache for high-speed artwork & GIF caching
        let memoryCapacity = 100 * 1024 * 1024
        let diskCapacity = 1024 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "desKTop_url_cache")

        // Strictly start with .accessory policy: zero presence in Dock or Cmd+Tab
        NSApp.setActivationPolicy(.accessory)

        // Preload branded icon for when window is opened
        if let iconImage = Bundle.main.image(forResource: "AppIcon") ??
                           NSImage(contentsOfFile: "/Users/joepeterson/development/desKTop/app/Resources/AppIcon.icns") {
            NSApp.applicationIconImage = iconImage
        }

        setupStatusItem()
        setupPopover()
        setupRotationScheduler()
        setupDigitalFrameFeatures()

        // Sync desktop state on launch immediately: checks repository and system wallpaper
        Task { @MainActor in
            let paused = await self.repository.isRotationPaused()
            self.viewModel.isPaused = paused
            await self.syncDesktopState(forceApplyIfExternal: true)
        }

        // Automatically install/refresh native macOS Screen Saver plugin in ~/Library/Screen Savers/
        _ = try? ScreenSaverInstaller.installOrUpdate()
        ScreenSaverManifest.syncExistingToContainers()
        Task {
            await self.vault.enforceCacheLimit()
            await self.repository.enrichSafetyMetadata()
        }

        // Automatically check for updates on launch if enabled
        if UserDefaults.standard.object(forKey: "autoCheckUpdates") == nil ||
           UserDefaults.standard.bool(forKey: "autoCheckUpdates") {
            Task {
                let res = await UpdateService.shared.checkForUpdates()
                if case .updateAvailable(let newVer, _, _, _) = res {
                    await MainActor.run {
                        self.viewModel.statusMessage = "Update \(newVer) available"
                    }
                }
            }
        }

        // React when user settings change (e.g. animation freeze, matte mode)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("didChangeUserSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let current = self.viewModel.currentToken else { return }
                await self.setTokenAsWallpaper(current)
            }
        }

        // React when system power source or Low Power Mode changes (AC <-> Battery)
        _ = PowerGuardian.shared
        NotificationCenter.default.addObserver(
            forName: PowerGuardian.powerStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let current = self.viewModel.currentToken else { return }
                let disableAnimations = UserDefaults.standard.bool(forKey: "disableAnimations")
                let pauseOnBattery = UserDefaults.standard.bool(forKey: "pauseOnBattery")
                let shouldFreeze = PowerGuardian.evaluateShouldFreeze(
                    disableAnimations: disableAnimations,
                    pauseOnBattery: pauseOnBattery,
                    isOnBattery: PowerGuardian.shared.isOnBattery,
                    isLowPowerModeEnabled: PowerGuardian.shared.isLowPowerModeEnabled
                )
                guard shouldFreeze != self.lastEvaluatedFreezeState else { return }
                if current.mediaCategory != .staticImage && current.mediaCategory != .vectorImage {
                    await self.setTokenAsWallpaper(current)
                } else {
                    self.lastEvaluatedFreezeState = shouldFreeze
                }
            }
        }

        // Return to accessory policy when all regular windows are closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let hasVisibleWindows = NSApp.windows.contains { w in
                    w.isVisible && w.canBecomeKey && w.level == .normal && !(w is NSPanel)
                }
                if !hasVisibleWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let button = statusItem?.button {
            togglePopover(button)
        }
        Task { @MainActor in
            await self.syncDesktopState(forceApplyIfExternal: false)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.unregisterAll()
        GalleryModeController.shared.stop()
        if let esc = interactiveEscMonitor {
            NSEvent.removeMonitor(esc)
            interactiveEscMonitor = nil
        }
        if let observer = desktopChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for controller in canvasControllers.values {
            controller.dismiss()
        }
        canvasControllers.removeAll()
    }

    private func handleDesktopImageChangedExternally() {
        guard let screen = NSScreen.main else { return }
        let currentSystemURL = NSWorkspace.shared.desktopImageURL(for: screen)
        if let applied = lastAppliedWallpaperURL, currentSystemURL == applied {
            isExternalWallpaperActive = false
            return
        }
        if let path = currentSystemURL?.path, path.contains("desKTop/ActiveWallpapers") {
            lastAppliedWallpaperURL = currentSystemURL
            isExternalWallpaperActive = false
            return
        }
        isExternalWallpaperActive = true
        if viewModel.currentToken != nil {
            viewModel.statusMessage = "External wallpaper active"
        }
    }

    private func syncDesktopState(forceApplyIfExternal: Bool) async {
        let tokens = await repository.getActiveRotationTokens()
        guard !tokens.isEmpty else {
            viewModel.statusMessage = "Ready — Add art in Gallery"
            viewModel.currentToken = nil
            return
        }

        let savedTokenId = UserDefaults.standard.string(forKey: "lastActiveTokenId")
        let tokenToDisplay: UnifiedToken
        if let savedId = savedTokenId, let found = tokens.first(where: { $0.id == savedId || $0.tokenId == savedId }) {
            tokenToDisplay = found
        } else if let current = viewModel.currentToken, tokens.contains(where: { $0.id == current.id }) {
            tokenToDisplay = current
        } else {
            tokenToDisplay = tokens.first!
        }

        guard let screen = NSScreen.main else { return }
        let currentSystemURL = NSWorkspace.shared.desktopImageURL(for: screen)

        let isOurWallpaper: Bool
        if let applied = lastAppliedWallpaperURL {
            isOurWallpaper = (currentSystemURL == applied)
        } else if let path = currentSystemURL?.path {
            isOurWallpaper = path.contains("desKTop/ActiveWallpapers")
        } else {
            isOurWallpaper = false
        }

        if !isOurWallpaper {
            isExternalWallpaperActive = true
            if forceApplyIfExternal || viewModel.currentToken == nil {
                await setTokenAsWallpaper(tokenToDisplay)
            } else {
                viewModel.currentToken = tokenToDisplay
                viewModel.statusMessage = "External wallpaper active"
            }
        } else {
            isExternalWallpaperActive = false
            viewModel.currentToken = tokenToDisplay
            viewModel.statusMessage = "Live on \(screen.localizedName)"
            if DesktopWallpaperState.shared.liveTokenId == nil {
                DesktopWallpaperState.shared.liveTokenId = tokenToDisplay.id
                DesktopWallpaperState.shared.phase = .live(tokenId: tokenToDisplay.id, tokenName: tokenToDisplay.name, modeLabel: "Desktop")
            }
        }
    }

    private func setupRotationScheduler() {
        Task {
            let intervalSeconds = await repository.getRotationInterval()
            let interval = RotationInterval(rawValue: intervalSeconds) ?? .fiveMinutes
            let isPaused = await repository.isRotationPaused()

            self.rotationScheduler = RotationScheduler(interval: interval) { [weak self] in
                Task { @MainActor in
                    await self?.rotateNext()
                }
            }
            self.rotationScheduler?.isPaused = isPaused

            // Listen for active rotation target, interval, or pause changes from Library or MenuBar
            self.rotationObserver = NotificationCenter.default.addObserver(
                forName: .didChangeActiveRotation,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    let newSecs = await self.repository.getRotationInterval()
                    let newInterval = RotationInterval(rawValue: newSecs) ?? .fiveMinutes
                    let paused = await self.repository.isRotationPaused()
                    self.rotationScheduler?.interval = newInterval
                    self.rotationScheduler?.isPaused = paused

                    // Coalesce / debounce rapid sequential updates (e.g. target change + unpause)
                    // so we do not launch multiple concurrent wallpaper swaps
                    self.pendingRotationChangeTask?.cancel()
                    if !paused {
                        self.pendingRotationChangeTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                            guard !Task.isCancelled else { return }
                            await self.rotateNext()
                        }
                    }
                }
            }

            self.nextWallpaperObserver = NotificationCenter.default.addObserver(
                forName: .didRequestNextWallpaper,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.rotateNext()
                }
            }
        }
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
        popover.contentSize = NSSize(width: 330, height: 390)
        popover.behavior = .transient
        popover.delegate = self

        let contentView = MenuBarPopoverWrapperView(
            viewModel: viewModel,
            onNext: { [weak self] in
                Task { await self?.rotateNext(force: true) }
            },
            onPrevious: { [weak self] in
                Task { await self?.rotatePrevious() }
            },
            onRestartAnimation: { [weak self] in
                self?.restartCurrentAnimation()
            },
            onToggleFavorite: { [weak self] in
                Task { await self?.toggleCurrentFavorite() }
            },
            onHideToken: { [weak self] in
                Task { await self?.hideCurrentTokenAndAdvance() }
            },
            onUndoLastHide: { [weak self] in
                Task { await self?.undoLastHide() }
            },
            onToggleInteractive: { [weak self] in
                self?.toggleInteractiveCanvas()
            },
            onToggleDesktopIcons: { [weak self] in
                let hidden = DesktopIconsManager.toggleDesktopIcons()
                self?.viewModel.isDesktopIconsHidden = hidden
            },
            onEnterGalleryMode: { [weak self] in
                self?.popover.performClose(nil)
                self?.enterGalleryMode()
            },
            onSaveToDownloads: { [weak self] in
                Task { await self?.saveCurrentArtworkToDownloads() }
            },
            onCopyObjktLink: { [weak self] in
                self?.copyCurrentObjktLink()
            },
            onOpenLibrary: { [weak self] in
                self?.openLibraryWindow()
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
            }
        )

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupDigitalFrameFeatures() {
        let hotkeysEnabled = UserDefaults.standard.object(forKey: "globalHotkeysEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "globalHotkeysEnabled")

        GlobalHotkeyManager.shared.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .nextArtwork:
                Task { await self.rotateNext() }
            case .previousArtwork:
                Task { await self.rotatePrevious() }
            case .togglePause:
                self.viewModel.isPaused.toggle()
            case .peekHUD:
                self.peekHUD()
            case .toggleDesktopIcons:
                let hidden = DesktopIconsManager.toggleDesktopIcons()
                self.viewModel.isDesktopIconsHidden = hidden
            case .toggleInteractive:
                self.toggleInteractiveCanvas()
            }
        }
        GlobalHotkeyManager.shared.setEnabled(hotkeysEnabled)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let current = self.viewModel.currentToken else { return }
                await self.setTokenAsWallpaper(current)
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("desKTop.peekHUD"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.peekHUD()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("desKTop.didChangeDigitalFrameSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hkEnabled = UserDefaults.standard.object(forKey: "globalHotkeysEnabled") == nil
                    ? true
                    : UserDefaults.standard.bool(forKey: "globalHotkeysEnabled")
                GlobalHotkeyManager.shared.setEnabled(hkEnabled)

                if let token = self.viewModel.currentToken {
                    self.showHUDForToken(token, forcePeek: false)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .didChangeDesktopIconsVisibility,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let hidden = notif.object as? Bool
            Task { @MainActor [weak self] in
                if let hidden {
                    self?.viewModel.isDesktopIconsHidden = hidden
                } else {
                    self?.viewModel.isDesktopIconsHidden = DesktopIconsManager.isDesktopIconsHidden
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("desKTop.openSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSettingsWindow()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("desKTop.openLibrary"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openLibraryWindow()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("desKTop.didChangeScreenSaverSource"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let token = self.viewModel.currentToken, let fileURL = self.lastAppliedFileURL else { return }
                await self.syncScreenSaverManifest(currentToken: token, currentFileURL: fileURL, currentCategory: self.lastAppliedCategory)
            }
        }
    }

    private func buildCanvasContentView(
        for token: UnifiedToken,
        fileURL: URL,
        category: MediaCategory,
        screen: NSScreen,
        initialMatte: NSColor
    ) -> (view: NSView, modeLabel: String) {
        switch category {
        case .animatedImage:
            let tokenDir = fileURL.deletingLastPathComponent()
            let webView = SandboxedArtWebView(tokenDirectory: tokenDir, frame: screen.frame)
            let objectFit = (viewModel.scaling == .fill) ? "cover" : (viewModel.scaling == .center ? "none" : "contain")
            let bgHex = initialMatte.hexString
            let fileName = fileURL.lastPathComponent
            let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body { width: 100vw; height: 100vh; overflow: hidden; background: \(bgHex); display: flex; align-items: center; justify-content: center; }
            img { width: 100%; height: 100%; object-fit: \(objectFit); }
            </style>
            </head>
            <body>
            <img src="desktop-art://isolated/\(encodedFileName)" />
            </body>
            </html>
            """
            webView.loadHTML(html, baseURL: URL(string: "desktop-art://isolated/"))
            return (webView, "Animated GIF")

        case .video:
            let muteAudio = UserDefaults.standard.object(forKey: "muteVideoAudio") == nil ? true : UserDefaults.standard.bool(forKey: "muteVideoAudio")
            let videoView = VideoWallpaperView(videoURL: fileURL, isMuted: muteAudio)
            return (videoView, "Video Loop")

        default:
            let webView = SandboxedArtWebView(frame: screen.frame)
            if token.mediaCategory == .aleatory, let alea = token.aleatory, let code = alea.code {
                let decompressed = (try? AleatoryRuntime.decompress(code: code, encoding: alea.encoding)) ?? code
                let harness = AleatoryRuntime.composeHTMLHarness(decompressedScript: decompressed, seed: alea.seed ?? "0")
                webView.loadHTML(harness)
            } else if token.mediaCategory == .bootloader, let desc = token.description {
                let html = BootloaderRuntime.composeHTMLDocument(script: desc, seed: "0")
                webView.loadHTML(html)
            } else {
                webView.webView.load(URLRequest(url: fileURL))
            }
            return (webView, "Generative")
        }
    }

    private func showHUDForToken(_ token: UnifiedToken, forcePeek: Bool) {
        let modeRaw = UserDefaults.standard.string(forKey: "hudDisplayMode") ?? HUDDisplayMode.transition.rawValue
        let mode = HUDDisplayMode(rawValue: modeRaw) ?? .transition
        let profiles = ArtistResolver.loadCachedProfiles()
        let artistNames = token.creators.prefix(2).map { creator -> String in
            let trimmed = creator.trimmingCharacters(in: .whitespacesAndNewlines)
            if let profile = profiles[trimmed] ?? profiles[trimmed.lowercased()] {
                return profile.displayName
            }
            if trimmed.count > 12 {
                return "\(trimmed.prefix(6))…\(trimmed.suffix(4))"
            }
            return trimmed
        }.joined(separator: ", ")

        ArtworkHUDWindowController.shared.show(
            token: token,
            artistDisplay: artistNames,
            mode: mode,
            forcePeek: forcePeek
        )
    }

    private func peekHUD() {
        guard let current = viewModel.currentToken else { return }
        showHUDForToken(current, forcePeek: true)
    }

    private func restartCurrentAnimation() {
        var restarted = false
        for controller in canvasControllers.values {
            if let videoView = controller.currentContentView as? VideoWallpaperView {
                videoView.restart()
                restarted = true
            } else if let webView = controller.currentContentView as? SandboxedArtWebView {
                webView.webView.reload()
                restarted = true
            }
        }
        if !restarted, let current = viewModel.currentToken {
            Task { await setTokenAsWallpaper(current) }
        } else {
            viewModel.statusMessage = "Replayed artwork"
        }
    }

    private func toggleCurrentFavorite() async {
        guard let current = viewModel.currentToken else { return }
        if let isFav = try? await repository.toggleFavoriteToken(id: current.id) {
            viewModel.isFavorite = isFav
            viewModel.statusMessage = isFav ? "Added to Favorites" : "Removed from Favorites"
        }
    }

    private func hideCurrentTokenAndAdvance() async {
        guard let current = viewModel.currentToken else { return }
        try? await repository.blacklistToken(id: current.id)
        viewModel.lastHiddenToken = current
        viewModel.statusMessage = "Hidden '\(current.name)'"
        await rotateNext()
    }

    private func undoLastHide() async {
        guard let hidden = viewModel.lastHiddenToken else { return }
        try? await repository.unblacklistToken(id: hidden.id)
        viewModel.lastHiddenToken = nil
        await setTokenAsWallpaper(hidden)
    }

    private func toggleInteractiveCanvas() {
        let nextInteractive = !viewModel.isInteractive
        setInteractiveMode(nextInteractive)
    }

    private func setInteractiveMode(_ interactive: Bool) {
        if let esc = interactiveEscMonitor {
            NSEvent.removeMonitor(esc)
            interactiveEscMonitor = nil
        }

        guard !canvasControllers.isEmpty else {
            viewModel.isInteractive = false
            return
        }

        viewModel.isInteractive = interactive
        for controller in canvasControllers.values {
            controller.setInteractive(interactive)
        }

        if interactive {
            viewModel.statusMessage = "Interactive Canvas (Esc to exit)"
            interactiveEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    self?.setInteractiveMode(false)
                    return nil
                }
                return event
            }
        } else if let current = viewModel.currentToken {
            viewModel.statusMessage = "Live (\(current.name))"
        }
    }

    private func enterGalleryMode() {
        if let current = viewModel.currentToken, let fileURL = lastAppliedFileURL {
            presentGalleryMode(token: current, fileURL: fileURL, category: lastAppliedCategory)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let targetToken: UnifiedToken?
            if let current = self.viewModel.currentToken {
                targetToken = current
            } else {
                targetToken = await self.repository.getActiveRotationTokens().first
            }
            guard let token = targetToken else { return }
            await self.setTokenAsWallpaper(token)
            if let fileURL = self.lastAppliedFileURL {
                self.presentGalleryMode(token: token, fileURL: fileURL, category: self.lastAppliedCategory)
            }
        }
    }

    private func presentGalleryMode(token: UnifiedToken, fileURL: URL, category: MediaCategory) {
        let profiles = ArtistResolver.loadCachedProfiles()
        let artistNames = token.creators.prefix(2).map { creator -> String in
            let trimmed = creator.trimmingCharacters(in: .whitespacesAndNewlines)
            if let profile = profiles[trimmed] ?? profiles[trimmed.lowercased()] {
                return profile.displayName
            }
            return trimmed.count > 12 ? "\(trimmed.prefix(6))…\(trimmed.suffix(4))" : trimmed
        }.joined(separator: ", ")

        GalleryModeController.shared.onNext = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.rotateNext(force: true)
            }
        }
        GalleryModeController.shared.onPrevious = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.rotatePrevious()
            }
        }
        GalleryModeController.shared.onTogglePause = { [weak self] in
            guard let self else { return }
            self.viewModel.isPaused.toggle()
            GalleryModeController.shared.updatePauseState(self.viewModel.isPaused)
        }
        GalleryModeController.shared.start(
            token: token,
            fileURL: fileURL,
            category: category,
            artistDisplay: artistNames,
            isPaused: viewModel.isPaused
        )
    }

    private func syncScreenSaverManifest(currentToken: UnifiedToken, currentFileURL: URL, currentCategory: MediaCategory) async {
        let profiles = ArtistResolver.loadCachedProfiles()
        let activeTokens = await repository.getActiveRotationTokens()
        let allTokens = await repository.getTokens()
        let galleries = await repository.getGalleries()
        let blacklistedIds = await repository.getBlacklist()
        let interval = await repository.getRotationInterval()

        let activeIds = Set(activeTokens.map(\.id))
        let defaultSourceId = UserDefaults.standard.string(forKey: "screenSaverSourceId") ?? "sameAsDesktop"
        let saverShuffle = UserDefaults.standard.bool(forKey: "screenSaverShuffle")

        var sources: [ScreenSaverSourceOption] = [
            ScreenSaverSourceOption(id: "sameAsDesktop", name: "Same as Desktop Rotation"),
            ScreenSaverSourceOption(id: "favorites", name: "Favorites"),
            ScreenSaverSourceOption(id: "allLibrary", name: "Entire Library")
        ]
        var galleryTokenMap: [String: Set<String>] = [:]
        for g in galleries {
            let gid = g.id.uuidString
            sources.append(ScreenSaverSourceOption(id: "gallery:\(gid)", name: g.name))
            galleryTokenMap[gid] = Set(g.matchingTokens(from: allTokens).map(\.id))
        }

        func artistDisplay(for t: UnifiedToken) -> String {
            t.creators.prefix(2).map { creator -> String in
                let trimmed = creator.trimmingCharacters(in: .whitespacesAndNewlines)
                if let profile = profiles[trimmed] ?? profiles[trimmed.lowercased()] {
                    return profile.displayName
                }
                return trimmed.count > 12 ? "\(trimmed.prefix(6))…\(trimmed.suffix(4))" : trimmed
            }.joined(separator: ", ")
        }

        func matchingGalleryIds(for t: UnifiedToken) -> [String] {
            galleryTokenMap.compactMap { (gid, ids) in
                ids.contains(t.id) ? gid : nil
            }
        }

        var items: [ScreenSaverManifestItem] = []
        var seenIds = Set<String>()

        // Always include the currently active token with its resolved file URL
        let currentFallback: String? = await {
            for uri in [currentToken.displayUri, currentToken.thumbnailUri].compactMap({ $0 }) {
                if let cached = await vault.localCachedURL(for: uri) {
                    return cached.path
                }
            }
            return nil
        }()
        items.append(ScreenSaverManifestItem(
            id: currentToken.id,
            title: currentToken.name,
            artistDisplay: artistDisplay(for: currentToken),
            marketplaceLabel: currentToken.marketplace.shortName,
            tokenId: currentToken.tokenId,
            category: currentCategory.rawValue,
            localMediaPath: currentFileURL.path,
            fallbackImagePath: currentFallback,
            isInDesktopRotation: activeIds.contains(currentToken.id),
            isFavorite: await repository.isTokenFavorite(id: currentToken.id),
            galleryIds: matchingGalleryIds(for: currentToken)
        ))
        seenIds.insert(currentToken.id)

        // Include cached tokens from active rotation first, then the rest of the library
        let orderedPool = activeTokens + allTokens.filter { !activeIds.contains($0.id) }
        for t in orderedPool where !seenIds.contains(t.id) && !blacklistedIds.contains(t.id) {
            let primaryPath = await { () -> String? in
                guard let uri = t.primaryWallpaperUri else { return nil }
                return await vault.localCachedURL(for: uri)?.path
            }()
            let fallbackPath = await { () -> String? in
                for uri in [t.displayUri, t.thumbnailUri].compactMap({ $0 }) {
                    if let cached = await vault.localCachedURL(for: uri) {
                        return cached.path
                    }
                }
                return nil
            }()
            guard primaryPath != nil || fallbackPath != nil else { continue }
            items.append(ScreenSaverManifestItem(
                id: t.id,
                title: t.name,
                artistDisplay: artistDisplay(for: t),
                marketplaceLabel: t.marketplace.shortName,
                tokenId: t.tokenId,
                category: t.mediaCategory.rawValue,
                localMediaPath: primaryPath,
                fallbackImagePath: fallbackPath,
                isInDesktopRotation: activeIds.contains(t.id),
                isFavorite: await repository.isTokenFavorite(id: t.id),
                galleryIds: matchingGalleryIds(for: t)
            ))
            seenIds.insert(t.id)
            if items.count >= 300 { break }
        }

        ScreenSaverManifest.write(ScreenSaverManifest(
            updatedAt: Date(),
            currentTokenId: currentToken.id,
            intervalSeconds: Double(interval),
            defaultSourceId: defaultSourceId,
            shuffle: saverShuffle,
            sources: sources,
            items: items
        ))
    }

    private func copyCurrentObjktLink() {
        guard let token = viewModel.currentToken,
              let urlString = token.marketplaceTokenURL?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        viewModel.statusMessage = "Copied \(token.marketplace.displayName) link"
    }

    private func saveCurrentArtworkToDownloads() async {
        guard let token = viewModel.currentToken else { return }
        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        guard let sourceURL = lastAppliedFileURL ?? lastAppliedWallpaperURL else { return }

        let safeBase = token.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        var destURL = downloadsDir.appendingPathComponent("\(safeBase.isEmpty ? token.tokenId : safeBase).\(ext)")

        var suffix = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            destURL = downloadsDir.appendingPathComponent("\(safeBase.isEmpty ? token.tokenId : safeBase)-\(suffix).\(ext)")
            suffix += 1
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            viewModel.statusMessage = "Saved \(destURL.lastPathComponent)"
        } catch {
            viewModel.statusMessage = "Save failed: \(error.localizedDescription)"
        }
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
            Task { @MainActor in
                await self.syncDesktopState(forceApplyIfExternal: false)
            }
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

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesMenuClicked), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)

        let infoItem = NSMenuItem(title: "About desKTop…", action: #selector(showAboutDialog), keyEquivalent: "i")
        infoItem.target = self
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit desKTop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc func openSettingsWindow() {
        openSettingsWindow(tab: .general)
    }

    func openSettingsWindow(tab: SettingsTab = .general) {
        if popover.isShown {
            popover.performClose(nil)
        }
        SettingsWindowController.shared.show(repository: repository, initialTab: tab)
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        openSettingsWindow()
    }

    @objc func showPreferencesWindow(_ sender: Any?) {
        openSettingsWindow()
    }

    @objc private func checkForUpdatesMenuClicked() {
        openSettingsWindow(tab: .general)
    }

    @objc private func openLibraryWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        LibraryWindowController.shared.show(repository: repository) { [weak self] token in
            self?.requestSetTokenAsWallpaper(token)
        }
    }

    private func requestSetTokenAsWallpaper(_ token: UnifiedToken) {
        applyWallpaperTask?.cancel()
        applyWallpaperTask = Task { @MainActor [weak self] in
            await self?.setTokenAsWallpaper(token)
        }
    }

    @objc private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "desKTop"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.2"
        alert.informativeText = "Version \(version)\n\nTurn your Mac desktop into a living Tezos art gallery.\n\na FAFOlab joint\nhttps://fafolab.xyz\n\nOpen source under The Unlicense."
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

    /// Resolves a decodable flat still image URL for the given token (frame 0 for GIF/video, poster for generative)
    private func resolveStillPosterURL(for token: UnifiedToken, primaryFileURL: URL, category: MediaCategory) async -> URL? {
        func isDecodableImage(_ url: URL) -> Bool {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 {
                return true
            }
            return NSImage(contentsOf: url) != nil
        }

        // 1. For images & GIFs/WebPs, the primary file itself decodes to frame 0
        if category == .staticImage || category == .animatedImage || category == .vectorImage || category == .audio3d || category == .unknown {
            if isDecodableImage(primaryFileURL) {
                return primaryFileURL
            }
        }

        // 2. For video assets, capture a crisp frame 0 PNG via AVAssetImageGenerator
        if category == .video {
            let snapDir = FileManager.default.temporaryDirectory.appendingPathComponent("desKTopSnapshots", isDirectory: true)
            try? FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)
            let snapURL = snapDir.appendingPathComponent("snap_\(token.tokenId).png")
            if (try? await StaticSnapshotGenerator.generateVideoSnapshot(from: primaryFileURL, at: .zero, outputURL: snapURL)) != nil {
                return snapURL
            }
        }

        // 3. Fallback to displayUri / thumbnailUri poster for generative, video, or un-decodable files
        for candidate in [token.displayUri, token.thumbnailUri].compactMap({ $0 }) {
            guard UnifiedToken.isVisualUri(candidate) else { continue }
            if let (altURL, _) = try? await vault.getOrFetchMedia(for: candidate), isDecodableImage(altURL) {
                return altURL
            }
        }

        return nil
    }

    func setTokenAsWallpaper(_ token: UnifiedToken) async {
        wallpaperRequestSeq &+= 1
        let mySeq = wallpaperRequestSeq

        guard let uri = token.primaryWallpaperUri else {
            viewModel.statusMessage = "No media available"
            DesktopWallpaperState.shared.loadingTokenId = nil
            DesktopWallpaperState.shared.phase = .failed(tokenId: token.id, message: "No media available")
            return
        }

        viewModel.statusMessage = "Fetching \(token.name)…"
        DesktopWallpaperState.shared.loadingTokenId = token.id
        DesktopWallpaperState.shared.phase = .loading(tokenId: token.id, message: "Fetching artwork…")

        do {
            let liveNonImageCategories: Set<MediaCategory> = [
                .video, .fxhash, .editArt, .interactiveHtml, .aleatory, .bootloader
            ]

            // Resolve primary media with visual fallback only when an image asset isn't decodable
            var fileURL: URL
            do {
                let (fURL, _) = try await vault.getOrFetchMedia(for: uri)
                if !liveNonImageCategories.contains(token.mediaCategory) && NSImage(contentsOf: fURL) == nil {
                    if let fallback = [token.displayUri, token.thumbnailUri].compactMap({ $0 }).first(where: { UnifiedToken.isVisualUri($0) && $0 != uri }) {
                        let (altURL, _) = try await vault.getOrFetchMedia(for: fallback)
                        fileURL = altURL
                    } else {
                        fileURL = fURL
                    }
                } else {
                    fileURL = fURL
                }
            } catch {
                if let fallback = [token.displayUri, token.thumbnailUri].compactMap({ $0 }).first(where: { UnifiedToken.isVisualUri($0) && $0 != uri }) {
                    let (altURL, _) = try await vault.getOrFetchMedia(for: fallback)
                    fileURL = altURL
                } else {
                    throw error
                }
            }

            guard mySeq == wallpaperRequestSeq, !Task.isCancelled else { return }
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

            // Sniff actual file bytes even if indexer metadata was generic
            var effectiveCategory = token.mediaCategory
            if effectiveCategory == .staticImage || effectiveCategory == .unknown {
                if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
                    let prefixData = fileHandle.readData(ofLength: 32)
                    try? fileHandle.close()
                    let sniffed = MediaTypeDetector.detect(data: prefixData)
                    if sniffed == .gif || sniffed == .webp {
                        effectiveCategory = .animatedImage
                    } else if sniffed == .mp4 {
                        effectiveCategory = .video
                    }
                }
            }

            DesktopWallpaperState.shared.phase = .loading(tokenId: token.id, message: "Applying to desktop…")
            viewModel.statusMessage = "Applying \(token.name)…"

            // Energy & Motion tuning check
            let disableAnimations = UserDefaults.standard.bool(forKey: "disableAnimations")
            let pauseOnBattery = UserDefaults.standard.bool(forKey: "pauseOnBattery")
            let shouldFreeze = PowerGuardian.evaluateShouldFreeze(
                disableAnimations: disableAnimations,
                pauseOnBattery: pauseOnBattery,
                isOnBattery: PowerGuardian.shared.isOnBattery,
                isLowPowerModeEnabled: PowerGuardian.shared.isLowPowerModeEnabled
            )
            self.lastEvaluatedFreezeState = shouldFreeze

            let matteModeRaw = UserDefaults.standard.string(forKey: "wallpaperMatteMode") ?? WallpaperMatteMode.dynamicArtwork.rawValue
            let matteMode = WallpaperMatteMode(rawValue: matteModeRaw) ?? .dynamicArtwork
            let customHex = UserDefaults.standard.string(forKey: "wallpaperCustomHex")

            setInteractiveMode(false)
            self.lastAppliedFileURL = fileURL
            self.lastAppliedCategory = effectiveCategory
            self.viewModel.isFavorite = await repository.isTokenFavorite(id: token.id)
            if GalleryModeController.shared.isActive {
                self.presentGalleryMode(token: token, fileURL: fileURL, category: effectiveCategory)
            }
            await self.syncScreenSaverManifest(currentToken: token, currentFileURL: fileURL, currentCategory: effectiveCategory)

            // Order screens with main display first and prune disconnected canvas controllers
            var orderedScreens = NSScreen.screens
            if let mainIdx = orderedScreens.firstIndex(where: { $0 == screen }), mainIdx != 0 {
                let mainScreen = orderedScreens.remove(at: mainIdx)
                orderedScreens.insert(mainScreen, at: 0)
            }
            let activeUUIDs = Set(orderedScreens.map { scr -> String in
                let sid = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                return DisplayManager.persistentUUID(for: sid)
            })
            for uuid in Array(canvasControllers.keys) where !activeUUIDs.contains(uuid) {
                canvasControllers[uuid]?.dismiss()
                canvasControllers.removeValue(forKey: uuid)
            }

            let multiMonitorRaw = UserDefaults.standard.string(forKey: "multiMonitorMode") ?? MultiMonitorMode.mirrored.rawValue
            let multiMonitorMode = MultiMonitorMode(rawValue: multiMonitorRaw) ?? .mirrored

            if shouldFreeze && effectiveCategory != .staticImage && effectiveCategory != .vectorImage && effectiveCategory != .audio3d && effectiveCategory != .unknown {
                let posterURL = await resolveStillPosterURL(for: token, primaryFileURL: fileURL, category: effectiveCategory)
                guard mySeq == wallpaperRequestSeq, !Task.isCancelled else { return }
                let matteColor = ArtworkMatteEngine.resolveMatteColor(imageURL: posterURL ?? fileURL, mode: matteMode, customHex: customHex)

                for controller in canvasControllers.values {
                    controller.dismiss()
                }

                let appliedURL: URL
                if let flatURL = posterURL {
                    appliedURL = try wallpaperService.setDesktopWallpaper(
                        imageURL: flatURL,
                        tokenId: token.tokenId,
                        for: nil,
                        scaling: viewModel.scaling,
                        matteColor: matteColor
                    )
                } else {
                    appliedURL = try wallpaperService.setSolidMatteWallpaper(
                        tokenId: token.tokenId,
                        for: nil,
                        matteColor: matteColor
                    )
                }
                self.lastAppliedWallpaperURL = appliedURL
                self.isExternalWallpaperActive = false
                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName) (Static Mode)"
                DesktopWallpaperState.shared.loadingTokenId = nil
                DesktopWallpaperState.shared.liveTokenId = token.id
                DesktopWallpaperState.shared.phase = .live(tokenId: token.id, tokenName: token.name, modeLabel: "Static Mode")
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")
                showHUDForToken(token, forcePeek: false)
                self.rotationScheduler?.restartTimer()
                return
            }

            switch effectiveCategory {
            case .animatedImage, .video, .fxhash, .aleatory, .bootloader, .editArt, .interactiveHtml:
                // Compute immediate matte color from fileURL if it is already an image/GIF (<3ms via ImageIO 64px thumbnail)
                let initialMatte = ArtworkMatteEngine.resolveMatteColor(imageURL: fileURL, mode: matteMode, customHex: customHex)

                // Mount live canvases across ALL connected screens (or primary screen in independent mode)
                let screensForPrimary: [NSScreen] = (multiMonitorMode == .independent && orderedScreens.count > 1)
                    ? [screen]
                    : orderedScreens

                var lastModeLabel = "Live"
                for targetScreen in screensForPrimary {
                    let targetSID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                    let targetUUID = DisplayManager.persistentUUID(for: targetSID)
                    let controller = canvasControllers[targetUUID] ?? DesktopCanvasWindowController(screen: targetScreen, displayUUID: targetUUID)
                    canvasControllers[targetUUID] = controller
                    controller.updateFrame(for: targetScreen)
                    controller.setBackgroundColor(initialMatte)

                    let built = buildCanvasContentView(
                        for: token,
                        fileURL: fileURL,
                        category: effectiveCategory,
                        screen: targetScreen,
                        initialMatte: initialMatte
                    )
                    controller.setCanvasContent(built.view)
                    controller.present()
                    lastModeLabel = built.modeLabel
                }

                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(orderedScreens.count > 1 ? "\(orderedScreens.count) Displays" : screen.localizedName) (\(lastModeLabel))"
                self.isExternalWallpaperActive = false
                DesktopWallpaperState.shared.loadingTokenId = nil
                DesktopWallpaperState.shared.liveTokenId = token.id
                DesktopWallpaperState.shared.phase = .live(tokenId: token.id, tokenName: token.name, modeLabel: lastModeLabel)
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")
                showHUDForToken(token, forcePeek: false)

                // Sync macOS underlying desktop wallpaper to the flat image of this SAME piece right behind the live panel
                let syncScaling = viewModel.scaling
                Task { @MainActor [weak self] in
                    guard let self = self, self.wallpaperRequestSeq == mySeq else { return }
                    let posterURL = await self.resolveStillPosterURL(for: token, primaryFileURL: fileURL, category: effectiveCategory)
                    guard self.wallpaperRequestSeq == mySeq else { return }
                    let finalMatte = ArtworkMatteEngine.resolveMatteColor(imageURL: posterURL ?? fileURL, mode: matteMode, customHex: customHex)
                    for targetScreen in screensForPrimary {
                        let targetSID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                        let targetUUID = DisplayManager.persistentUUID(for: targetSID)
                        self.canvasControllers[targetUUID]?.setBackgroundColor(finalMatte)
                    }
                    let targetScreenParam: NSScreen? = (multiMonitorMode == .independent && orderedScreens.count > 1) ? screen : nil
                    if let flatURL = posterURL,
                       let appliedURL = try? self.wallpaperService.setDesktopWallpaper(
                        imageURL: flatURL,
                        tokenId: token.tokenId,
                        for: targetScreenParam,
                        scaling: syncScaling,
                        matteColor: finalMatte
                       ) {
                        self.lastAppliedWallpaperURL = appliedURL
                    } else if let appliedURL = try? self.wallpaperService.setSolidMatteWallpaper(
                        tokenId: token.tokenId,
                        for: targetScreenParam,
                        matteColor: finalMatte
                    ) {
                        self.lastAppliedWallpaperURL = appliedURL
                    }
                }

            default:
                let posterURL = await resolveStillPosterURL(for: token, primaryFileURL: fileURL, category: effectiveCategory)
                guard mySeq == wallpaperRequestSeq, !Task.isCancelled else { return }
                let matteColor = ArtworkMatteEngine.resolveMatteColor(imageURL: posterURL ?? fileURL, mode: matteMode, customHex: customHex)

                for controller in canvasControllers.values {
                    controller.dismiss()
                }

                let targetScreenParam: NSScreen? = (multiMonitorMode == .independent && orderedScreens.count > 1) ? screen : nil
                let appliedURL = try wallpaperService.setDesktopWallpaper(
                    imageURL: posterURL ?? fileURL,
                    tokenId: token.tokenId,
                    for: targetScreenParam,
                    scaling: viewModel.scaling,
                    matteColor: matteColor
                )
                self.lastAppliedWallpaperURL = appliedURL
                self.isExternalWallpaperActive = false
                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(orderedScreens.count > 1 ? "\(orderedScreens.count) Displays" : screen.localizedName)"
                DesktopWallpaperState.shared.loadingTokenId = nil
                DesktopWallpaperState.shared.liveTokenId = token.id
                DesktopWallpaperState.shared.phase = .live(tokenId: token.id, tokenName: token.name, modeLabel: "Static")
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")
                showHUDForToken(token, forcePeek: false)
            }

            // Independent Multi-Monitor mode: populate secondary screens with distinct artworks
            if multiMonitorMode == .independent && orderedScreens.count > 1 {
                let secondaryScreens = Array(orderedScreens.dropFirst())
                Task { @MainActor [weak self] in
                    guard let self = self, self.wallpaperRequestSeq == mySeq else { return }
                    await self.populateIndependentSecondaryScreens(
                        secondaryScreens,
                        excludingTokenId: token.id,
                        shouldFreeze: shouldFreeze,
                        matteMode: matteMode,
                        customHex: customHex,
                        seq: mySeq
                    )
                }
            }

            self.rotationScheduler?.restartTimer()
        } catch {
            guard mySeq == wallpaperRequestSeq else { return }
            self.viewModel.statusMessage = "Error: \(error.localizedDescription)"
            DesktopWallpaperState.shared.loadingTokenId = nil
            DesktopWallpaperState.shared.phase = .failed(tokenId: token.id, message: error.localizedDescription)
        }
    }

    private func populateIndependentSecondaryScreens(
        _ screens: [NSScreen],
        excludingTokenId: String,
        shouldFreeze: Bool,
        matteMode: WallpaperMatteMode,
        customHex: String?,
        seq: UInt64
    ) async {
        let pool = await repository.getActiveRotationTokens().filter { $0.id != excludingTokenId }
        guard !pool.isEmpty else { return }
        var candidates = pool.shuffled()

        for secScreen in screens {
            guard wallpaperRequestSeq == seq, !candidates.isEmpty else { break }
            let secToken = candidates.removeFirst()
            guard let uri = secToken.primaryWallpaperUri, let (secFileURL, _) = try? await vault.getOrFetchMedia(for: uri) else {
                continue
            }
            guard wallpaperRequestSeq == seq else { return }

            let secCat = secToken.mediaCategory
            let secSID = secScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
            let secUUID = DisplayManager.persistentUUID(for: secSID)
            let isDynamic = !shouldFreeze && (secCat == .animatedImage || secCat == .video || secCat == .fxhash || secCat == .aleatory || secCat == .bootloader || secCat == .editArt || secCat == .interactiveHtml)

            if isDynamic {
                let matte = ArtworkMatteEngine.resolveMatteColor(imageURL: secFileURL, mode: matteMode, customHex: customHex)
                let controller = canvasControllers[secUUID] ?? DesktopCanvasWindowController(screen: secScreen, displayUUID: secUUID)
                canvasControllers[secUUID] = controller
                controller.updateFrame(for: secScreen)
                controller.setBackgroundColor(matte)
                let built = buildCanvasContentView(for: secToken, fileURL: secFileURL, category: secCat, screen: secScreen, initialMatte: matte)
                controller.setCanvasContent(built.view)
                controller.present()
            } else {
                canvasControllers[secUUID]?.dismiss()
                let posterURL = await resolveStillPosterURL(for: secToken, primaryFileURL: secFileURL, category: secCat)
                guard wallpaperRequestSeq == seq else { return }
                let matte = ArtworkMatteEngine.resolveMatteColor(imageURL: posterURL ?? secFileURL, mode: matteMode, customHex: customHex)
                _ = try? wallpaperService.setDesktopWallpaper(
                    imageURL: posterURL ?? secFileURL,
                    tokenId: secToken.tokenId,
                    for: secScreen,
                    scaling: viewModel.scaling,
                    matteColor: matte
                )
            }
        }
    }

    private func rotateNext(force: Bool = false) async {
        guard !isRotating else { return }
        isRotating = true
        defer { isRotating = false }

        if !force {
            let isPaused = await repository.isRotationPaused()
            if isPaused { return }
        }

        let tokens = await repository.getActiveRotationTokens()
        guard !tokens.isEmpty else { return }

        let isShuffle = await repository.isRotationShuffle()
        let nextToken: UnifiedToken

        if isShuffle && tokens.count > 1 {
            let currentId = viewModel.currentToken?.id
            let pool = tokens.filter { $0.id != currentId }
            nextToken = pool.randomElement() ?? tokens.randomElement()!
        } else if let current = viewModel.currentToken,
                  let idx = tokens.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = (idx + 1) % tokens.count
            nextToken = tokens[nextIdx]
        } else if let savedId = UserDefaults.standard.string(forKey: "lastActiveTokenId"),
                  let idx = tokens.firstIndex(where: { $0.id == savedId || $0.tokenId == savedId }) {
            let nextIdx = (idx + 1) % tokens.count
            nextToken = tokens[nextIdx]
        } else {
            nextToken = tokens.first!
        }

        await setTokenAsWallpaper(nextToken)
    }

    private func rotatePrevious() async {
        let tokens = await repository.getActiveRotationTokens()
        guard !tokens.isEmpty else { return }

        if let current = viewModel.currentToken,
           let idx = tokens.firstIndex(where: { $0.id == current.id }) {
            let prevIdx = (idx - 1 + tokens.count) % tokens.count
            await setTokenAsWallpaper(tokens[prevIdx])
        } else if let savedId = UserDefaults.standard.string(forKey: "lastActiveTokenId"),
                  let idx = tokens.firstIndex(where: { $0.id == savedId || $0.tokenId == savedId }) {
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
            SettingsView(repository: appDelegate.repository)
        }
    }
}
