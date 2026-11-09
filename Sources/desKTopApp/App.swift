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
    private var canvasControllers: [String: DesktopCanvasWindowController] = [:]
    private var rotationScheduler: RotationScheduler?
    private var rotationObserver: NSObjectProtocol?
    private var nextWallpaperObserver: NSObjectProtocol?
    private var isRotating: Bool = false
    private var pendingRotationChangeTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        alert.informativeText = "Version 1.0.0\n\nTurn your Mac desktop into a living Tezos art gallery.\n\nCreated by FAFOlab (a FAFOlab joint)\nhttps://fafolab.xyz\n\nOpen source under The Unlicense."
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
            let (fileURL, _) = try await vault.getOrFetchMedia(for: uri)
            guard let screen = NSScreen.main else { return }
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
            let displayUUID = DisplayManager.persistentUUID(for: screenID)

            // Resolve border / letterbox matte color based on artwork & user preference
            let matteModeRaw = UserDefaults.standard.string(forKey: "wallpaperMatteMode") ?? WallpaperMatteMode.dynamicArtwork.rawValue
            let matteMode = WallpaperMatteMode(rawValue: matteModeRaw) ?? .dynamicArtwork
            let customHex = UserDefaults.standard.string(forKey: "wallpaperCustomHex")
            let matteColor = ArtworkMatteEngine.resolveMatteColor(imageURL: fileURL, mode: matteMode, customHex: customHex)

            switch token.mediaCategory {
            case .animatedImage:
                // Animate GIF live on desktop canvas behind desktop icons
                let controller = canvasControllers[displayUUID] ?? DesktopCanvasWindowController(screen: screen, displayUUID: displayUUID)
                canvasControllers[displayUUID] = controller
                controller.setBackgroundColor(matteColor)

                let imageView = NSImageView(frame: screen.frame)
                imageView.imageScaling = viewModel.scaling == .fill ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
                imageView.animates = true
                imageView.canDrawSubviewsIntoLayer = true
                if let data = try? Data(contentsOf: fileURL), let img = NSImage(data: data) {
                    imageView.image = img
                    imageView.animates = true
                }
                controller.setCanvasContent(imageView)
                controller.present()

                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName) (Animated GIF)"

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

            default:
                // Still wallpaper: dismiss dynamic canvas and set image via NSWorkspace
                if let controller = canvasControllers[displayUUID] {
                    controller.dismiss()
                }

                _ = try wallpaperService.setDesktopWallpaper(
                    imageURL: fileURL,
                    tokenId: token.tokenId,
                    for: screen,
                    scaling: viewModel.scaling,
                    matteColor: matteColor
                )
                self.viewModel.currentToken = token
                self.viewModel.statusMessage = "Live on \(screen.localizedName)"
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
