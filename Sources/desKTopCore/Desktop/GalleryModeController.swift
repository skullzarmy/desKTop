import AppKit
import AVFoundation
import SwiftUI
import WebKit

private struct GalleryPlaqueOverlayView: View {
    let title: String
    let artist: String
    let badge: String
    let isPaused: Bool
    let isVisible: Bool
    let onExit: () -> Void

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    Button(action: onExit) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Exit Gallery Mode")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.78))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                    .padding(.trailing, 28)
                }

                Spacer()

                HStack(alignment: .bottom) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.169, green: 0.447, blue: 1.0))
                            .frame(width: 3, height: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                if !artist.isEmpty {
                                    Text(artist)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(Color.white.opacity(0.78))
                                        .lineLimit(1)
                                }

                                if !badge.isEmpty {
                                    Text(badge)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color.white.opacity(0.7))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                if isPaused {
                                    Text("PAUSED")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.18))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.84))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.5), radius: 18, x: 0, y: 8)

                    Spacer()

                    Text("←/→ Navigate  ·  Space Pause  ·  I Info  ·  Esc Exit")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.62))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.72))
                        )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
            }
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .allowsHitTesting(isVisible)
    }
}

private final class GalleryStageWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Fullscreen interactive exhibition mode inside desKTop (separate from macOS Screen Saver).
@MainActor
public final class GalleryModeController {
    public static let shared = GalleryModeController()

    public private(set) var isActive: Bool = false

    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onTogglePause: (() -> Void)?
    public var onExit: (() -> Void)?

    private var stageWindow: GalleryStageWindow?
    private var curtainWindows: [NSWindow] = []
    private var mediaContainer: NSView?
    private var overlayHostingView: NSHostingView<GalleryPlaqueOverlayView>?

    private var currentImageView: NSImageView?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?
    private var webView: WKWebView?

    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var fadeTask: Task<Void, Never>?

    private var currentTitle: String = ""
    private var currentArtist: String = ""
    private var currentBadge: String = ""
    private var currentPaused: Bool = false
    private var pinPlaque: Bool = false
    private var overlayVisible: Bool = true

    private init() {}

    public func start(
        token: UnifiedToken,
        fileURL: URL,
        category: MediaCategory,
        artistDisplay: String,
        isPaused: Bool
    ) {
        if !isActive {
            setupWindows()
            installEventMonitors()
            isActive = true
        }

        currentTitle = token.name.isEmpty ? "Untitled" : token.name
        currentArtist = artistDisplay
        currentBadge = category.displayName
        currentPaused = isPaused

        renderMedia(fileURL: fileURL, category: category)
        showOverlayTemporarily()
    }

    public func updatePauseState(_ isPaused: Bool) {
        guard isActive else { return }
        currentPaused = isPaused
        applyPauseToActiveMedia(isPaused)
        showOverlayTemporarily()
    }

    private func applyPauseToActiveMedia(_ paused: Bool) {
        if let imageView = currentImageView {
            imageView.animates = !paused
        }
        if let player {
            if paused {
                player.pause()
            } else {
                player.play()
            }
        }
        if let webView {
            let flag = paused ? "true" : "false"
            webView.evaluateJavaScript("window.__desKTopSetPaused && window.__desKTopSetPaused(\(flag));", completionHandler: nil)
        }
    }

    public func stop() {
        guard isActive else { return }
        isActive = false
        pinPlaque = false

        fadeTask?.cancel()
        fadeTask = nil

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

        clearMedia()

        stageWindow?.orderOut(nil)
        stageWindow = nil
        mediaContainer = nil
        overlayHostingView = nil

        for curtain in curtainWindows {
            curtain.orderOut(nil)
        }
        curtainWindows.removeAll()

        NSCursor.unhide()
        onExit?()
    }

    // MARK: - Window Setup

    private func setupWindows() {
        let primaryScreen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens.first

        guard let targetScreen = primaryScreen else { return }

        let window = GalleryStageWindow(
            contentRect: targetScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        window.level = .mainMenu + 2
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true

        let rootView = NSView(frame: NSRect(origin: .zero, size: targetScreen.frame.size))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor
        rootView.autoresizingMask = [.width, .height]

        let mediaView = NSView(frame: rootView.bounds)
        mediaView.wantsLayer = true
        mediaView.layer?.backgroundColor = NSColor.black.cgColor
        mediaView.autoresizingMask = [.width, .height]
        rootView.addSubview(mediaView)
        self.mediaContainer = mediaView

        let hosting = NSHostingView(rootView: GalleryPlaqueOverlayView(
            title: "",
            artist: "",
            badge: "",
            isPaused: false,
            isVisible: true,
            onExit: { [weak self] in self?.stop() }
        ))
        hosting.frame = rootView.bounds
        hosting.autoresizingMask = [.width, .height]
        rootView.addSubview(hosting)
        self.overlayHostingView = hosting

        window.contentView = rootView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.stageWindow = window

        for screen in NSScreen.screens where screen != targetScreen {
            let curtain = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            curtain.level = .mainMenu + 1
            curtain.backgroundColor = .black
            curtain.isOpaque = true
            curtain.hasShadow = false
            curtain.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            curtain.orderFrontRegardless()
            curtainWindows.append(curtain)
        }
    }

    // MARK: - Media Rendering

    private func clearMedia() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil

        currentImageView = nil
        mediaContainer?.subviews.forEach { $0.removeFromSuperview() }
    }

    private static func makePauseShimScript(initiallyPaused: Bool) -> String {
        let initialFlag = initiallyPaused ? "true" : "false"
        return """
    (function() {
      if (window.__desKTopPauseInstalled) return;
      window.__desKTopPauseInstalled = true;
      window.__desKTopPaused = \(initialFlag);
      var origRAF = window.requestAnimationFrame.bind(window);
      var pending = [];
      window.requestAnimationFrame = function(cb) {
        if (window.__desKTopPaused) {
          pending.push(cb);
          return 0;
        }
        return origRAF(cb);
      };
      window.__desKTopSetPaused = function(paused) {
        window.__desKTopPaused = !!paused;
        document.querySelectorAll('video, audio').forEach(function(m) {
          if (paused) { try { m.pause(); } catch(e) {} }
          else { try { m.play(); } catch(e) {} }
        });
        if (document.documentElement) {
          document.documentElement.style.animationPlayState = paused ? 'paused' : 'running';
        }
        if (!paused && pending.length > 0) {
          var q = pending.splice(0, pending.length);
          q.forEach(function(cb) { origRAF(cb); });
        }
      };
    })();
    """
    }

    private func renderMedia(fileURL: URL, category: MediaCategory) {
        clearMedia()
        guard let container = mediaContainer else { return }

        switch category {
        case .video:
            let avPlayer = AVPlayer(url: fileURL)
            let muteAudio = UserDefaults.standard.object(forKey: "muteVideoAudio") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "muteVideoAudio")
            avPlayer.isMuted = muteAudio

            let layer = AVPlayerLayer(player: avPlayer)
            layer.frame = container.bounds
            layer.videoGravity = .resizeAspect
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            container.layer?.addSublayer(layer)

            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: avPlayer.currentItem,
                queue: .main
            ) { [weak avPlayer] _ in
                avPlayer?.seek(to: .zero)
                avPlayer?.play()
            }

            if !currentPaused {
                avPlayer.play()
            }
            self.player = avPlayer
            self.playerLayer = layer

        case .interactiveHtml, .aleatory, .bootloader, .editArt, .fxhash, .audio3d:
            let config = WKWebViewConfiguration()
            config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let userScript = WKUserScript(source: Self.makePauseShimScript(initiallyPaused: currentPaused), injectionTime: .atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(userScript)
            let web = WKWebView(frame: container.bounds, configuration: config)
            web.autoresizingMask = [.width, .height]
            web.setValue(false, forKey: "drawsBackground")
            container.addSubview(web)

            if fileURL.isFileURL {
                web.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
            } else {
                web.load(URLRequest(url: fileURL))
            }
            self.webView = web
            if currentPaused {
                web.evaluateJavaScript("window.__desKTopSetPaused && window.__desKTopSetPaused(true);", completionHandler: nil)
            }

        case .staticImage, .vectorImage, .animatedImage, .unknown:
            let imageView = NSImageView(frame: container.bounds.insetBy(dx: 36, dy: 36))
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.animates = !currentPaused
            imageView.image = NSImage(contentsOf: fileURL)
            container.addSubview(imageView)
            self.currentImageView = imageView
        }
    }

    // MARK: - Overlay & Input

    private func refreshOverlay() {
        overlayHostingView?.rootView = GalleryPlaqueOverlayView(
            title: currentTitle,
            artist: currentArtist,
            badge: currentBadge,
            isPaused: currentPaused,
            isVisible: overlayVisible || pinPlaque,
            onExit: { [weak self] in self?.stop() }
        )
    }

    private func showOverlayTemporarily() {
        overlayVisible = true
        refreshOverlay()
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self, self.isActive else { return }
            self.overlayVisible = false
            self.refreshOverlay()
            if !self.pinPlaque {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }
            switch event.keyCode {
            case 53, 12: // Esc or Q
                self.stop()
                return nil
            case 123: // Left Arrow
                self.onPrevious?()
                return nil
            case 124: // Right Arrow
                self.onNext?()
                return nil
            case 49: // Space
                self.onTogglePause?()
                return nil
            case 34: // I
                self.pinPlaque.toggle()
                self.refreshOverlay()
                return nil
            default:
                return event
            }
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            guard let self, self.isActive else { return event }
            self.showOverlayTemporarily()
            return event
        }
    }
}
