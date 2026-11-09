import SwiftUI
import AppKit
import Combine
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
    let onOpenSettings: () -> Void

    var body: some View {
        MenuBarContentView(
            currentToken: $viewModel.currentToken,
            isPaused: $viewModel.isPaused,
            scaling: $viewModel.scaling,
            statusMessage: viewModel.statusMessage,
            onNext: onNext,
            onPrevious: onPrevious,
            onRestartAnimation: onRestartAnimation,
            onOpenLibrary: onOpenLibrary,
            onOpenSettings: onOpenSettings
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

        // Sync desktop state on launch immediately: checks repository and system wallpaper
        Task { @MainActor in
            let paused = await self.repository.isRotationPaused()
            self.viewModel.isPaused = paused
            await self.syncDesktopState(forceApplyIfExternal: true)
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
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
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
        if popover.isShown {
            popover.performClose(nil)
        }
        SettingsWindowController.shared.show(repository: repository)
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        openSettingsWindow()
    }

    @objc func showPreferencesWindow(_ sender: Any?) {
        openSettingsWindow()
    }

    @objc private func checkForUpdatesMenuClicked() {
        openSettingsWindow()
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
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

    func setTokenAsWallpaper(_ token: UnifiedToken) async {
        guard let uri = token.primaryWallpaperUri else {
            viewModel.statusMessage = "No media available"
            return
        }

        viewModel.statusMessage = "Loading \(token.name)..."
        do {
            // Resolve wallpaper media with automatic visual fallback if artifact is raw JSON or text
            var fileURL: URL
            do {
                let (fURL, _) = try await vault.getOrFetchMedia(for: uri)
                let isDecodable = (NSImage(contentsOf: fURL) != nil)
                if !isDecodable && token.mediaCategory != .interactiveHtml && token.mediaCategory != .aleatory && token.mediaCategory != .bootloader {
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

            guard let screen = NSScreen.main else { return }
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
            let displayUUID = DisplayManager.persistentUUID(for: screenID)

            // Resolve border / letterbox matte color based on artwork & user preference
            let matteModeRaw = UserDefaults.standard.string(forKey: "wallpaperMatteMode") ?? WallpaperMatteMode.dynamicArtwork.rawValue
            let matteMode = WallpaperMatteMode(rawValue: matteModeRaw) ?? .dynamicArtwork
            let customHex = UserDefaults.standard.string(forKey: "wallpaperCustomHex")
            let matteColor = ArtworkMatteEngine.resolveMatteColor(imageURL: fileURL, mode: matteMode, customHex: customHex)

            // Detect if media is animated GIF from file header even if indexer metadata was generic
            var effectiveCategory = token.mediaCategory
            if effectiveCategory == .staticImage || effectiveCategory == .unknown {
                if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
                    let prefixData = fileHandle.readData(ofLength: 32)
                    try? fileHandle.close()
                    if MediaTypeDetector.detect(data: prefixData) == .gif {
                        effectiveCategory = .animatedImage
                    }
                }
            }

            // Energy & Motion tuning check:
            let disableAnimations = UserDefaults.standard.bool(forKey: "disableAnimations")
            let pauseOnBattery = UserDefaults.standard.bool(forKey: "pauseOnBattery")
            let shouldFreeze = disableAnimations || (pauseOnBattery && PowerGuardian.shared.isOnBattery) || PowerGuardian.shared.isLowPowerModeEnabled

            if shouldFreeze && (effectiveCategory == .animatedImage || effectiveCategory == .video || effectiveCategory == .fxhash || effectiveCategory == .aleatory || effectiveCategory == .bootloader || effectiveCategory == .editArt || effectiveCategory == .interactiveHtml) {
                if let controller = canvasControllers[displayUUID] {
                    controller.dismiss()
                }

                let appliedURL = try wallpaperService.setDesktopWallpaper(
                    imageURL: fileURL,
                    tokenId: token.tokenId,
                    for: nil,
                    scaling: viewModel.scaling,
                    matteColor: matteColor
                )
                self.lastAppliedWallpaperURL = appliedURL
                self.isExternalWallpaperActive = false
                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName) (Static Mode)"
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")
                self.rotationScheduler?.restartTimer()
                return
            }

            switch effectiveCategory {
            case .animatedImage:
                // Hardware-accelerated WebKit canvas for animated GIFs / WebP: 0% runaway CPU
                let controller = canvasControllers[displayUUID] ?? DesktopCanvasWindowController(screen: screen, displayUUID: displayUUID)
                canvasControllers[displayUUID] = controller
                controller.setBackgroundColor(matteColor)

                let tokenDir = fileURL.deletingLastPathComponent()
                let webView = SandboxedArtWebView(tokenDirectory: tokenDir, frame: screen.frame)
                let objectFit = (viewModel.scaling == .fill) ? "cover" : (viewModel.scaling == .center ? "none" : "contain")
                let bgHex = matteColor.hexString
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
                controller.setCanvasContent(webView)
                controller.present()

                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName) (Animated GIF)"
                self.isExternalWallpaperActive = false
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")

            case .video:
                // Loop video seamlessly on desktop canvas
                let controller = canvasControllers[displayUUID] ?? DesktopCanvasWindowController(screen: screen, displayUUID: displayUUID)
                canvasControllers[displayUUID] = controller
                controller.setBackgroundColor(matteColor)

                let videoView = VideoWallpaperView(videoURL: fileURL)
                controller.setCanvasContent(videoView)
                controller.present()

                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName) (Video Loop)"
                self.isExternalWallpaperActive = false
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")

            case .fxhash, .aleatory, .bootloader, .editArt, .interactiveHtml:
                // Run generative WebGL/HTML engine on desktop canvas
                let controller = canvasControllers[displayUUID] ?? DesktopCanvasWindowController(screen: screen, displayUUID: displayUUID)
                canvasControllers[displayUUID] = controller
                controller.setBackgroundColor(matteColor)

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
                controller.setCanvasContent(webView)
                controller.present()

                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName) (Generative)"
                self.isExternalWallpaperActive = false
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")

            default:
                // Still wallpaper: dismiss dynamic canvas and set image via NSWorkspace
                if let controller = canvasControllers[displayUUID] {
                    controller.dismiss()
                }

                let appliedURL = try wallpaperService.setDesktopWallpaper(
                    imageURL: fileURL,
                    tokenId: token.tokenId,
                    for: nil,
                    scaling: viewModel.scaling,
                    matteColor: matteColor
                )
                self.lastAppliedWallpaperURL = appliedURL
                self.isExternalWallpaperActive = false
                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName)"
                UserDefaults.standard.set(token.id, forKey: "lastActiveTokenId")
            }

            // Always reset the timer to the FULL interval whenever a new wallpaper is applied.
            // This prevents unexpected swaps 30 seconds after setting!
            self.rotationScheduler?.restartTimer()
        } catch {
            self.viewModel.statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func rotateNext() async {
        guard !isRotating else { return }
        isRotating = true
        defer { isRotating = false }

        let isPaused = await repository.isRotationPaused()
        if isPaused { return }

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
