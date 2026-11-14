import AppKit
import AVFoundation
import Foundation
import ScreenSaver

private struct ManifestSource: Decodable {
    let id: String
    let name: String
}

private struct ManifestItem: Decodable {
    let id: String
    let title: String
    let artistDisplay: String
    let marketplaceLabel: String
    let tokenId: String
    let category: String
    let localMediaPath: String?
    let fallbackImagePath: String?
    let isInDesktopRotation: Bool?
    let isFavorite: Bool?
    let galleryIds: [String]?
}

private struct Manifest: Decodable {
    let currentTokenId: String?
    let intervalSeconds: Double
    let defaultSourceId: String?
    let shuffle: Bool?
    let sources: [ManifestSource]?
    let items: [ManifestItem]
}

@objc(desKTopScreenSaverView)
public final class desKTopScreenSaverView: ScreenSaverView {
    private static let moduleIdentifier = "xyz.fafolab.desktop.saver"
    private static let showPlaqueDefaultsKey = "desKTopSaverShowPlaque"
    private static let customIntervalDefaultsKey = "desKTopSaverIntervalSeconds"
    private static let fillScreenDefaultsKey = "desKTopSaverFillScreen"
    private static let selectedSourceDefaultsKey = "desKTopSaverSourceId"
    private static let shuffleDefaultsKey = "desKTopSaverShuffle"

    private var saverDefaults: UserDefaults {
        ScreenSaverDefaults(forModuleWithName: Self.moduleIdentifier) ?? UserDefaults.standard
    }

    private var allItems: [ManifestItem] = []
    private var items: [ManifestItem] = []
    private var availableSources: [ManifestSource] = []
    private var manifestDefaultSourceId: String = "sameAsDesktop"
    private var manifestShuffle: Bool = false
    private var currentIndex: Int = 0
    private var lastRotationDate: Date = .distantPast
    private var manifestInterval: TimeInterval = 300

    private var imageView: NSImageView?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: Any?
    private var plaqueBox: NSView?
    private var titleLabel: NSTextField?
    private var subtitleLabel: NSTextField?

    private var configSheetPanel: NSPanel?
    private var sourcePopup: NSPopUpButton?
    private var sourcePopupIds: [String] = []
    private var plaqueCheckbox: NSButton?
    private var fillScreenCheckbox: NSButton?
    private var shuffleCheckbox: NSButton?
    private var intervalPopup: NSPopUpButton?
    private var statusLabel: NSTextField?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0

        let iv = NSImageView(frame: bounds)
        iv.autoresizingMask = [.width, .height]
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.animates = true
        iv.isHidden = true
        addSubview(iv)
        self.imageView = iv

        let box = NSView(frame: .zero)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        box.layer?.cornerRadius = 8

        let tLabel = NSTextField(labelWithString: "")
        tLabel.font = NSFont.systemFont(ofSize: isPreview ? 10 : 15, weight: .semibold)
        tLabel.textColor = .white
        tLabel.lineBreakMode = .byTruncatingTail

        let sLabel = NSTextField(labelWithString: "")
        sLabel.font = NSFont.systemFont(ofSize: isPreview ? 8 : 12, weight: .regular)
        sLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        sLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [tLabel, sLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8)
        ])

        box.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isPreview ? 12 : 36),
            box.bottomAnchor.constraint(equalTo: bottomAnchor, constant: isPreview ? -12 : -36),
            box.widthAnchor.constraint(lessThanOrEqualToConstant: isPreview ? 220 : 480)
        ])

        self.plaqueBox = box
        self.titleLabel = tLabel
        self.subtitleLabel = sLabel

        loadManifest()
        applyScalingPreference()
        displayCurrentItem()
    }

    public override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    public override func startAnimation() {
        super.startAnimation()
        loadManifest()
        applyScalingPreference()
        if !items.isEmpty && imageView?.isHidden == true && playerLayer == nil {
            displayCurrentItem()
        }
        player?.play()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    public override func animateOneFrame() {
        guard items.count > 1 else { return }
        let interval = effectiveIntervalSeconds()
        guard interval > 0 else { return }
        if Date().timeIntervalSince(lastRotationDate) >= interval {
            if effectiveShuffle() {
                currentIndex = Int.random(in: 0..<items.count)
            } else {
                currentIndex = (currentIndex + 1) % items.count
            }
            displayCurrentItem()
        }
    }

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        if let panel = configSheetPanel {
            loadManifest()
            syncConfigureSheetState()
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "desKTop Screen Saver Options"

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 290))

        let header = NSTextField(labelWithString: "desKTop — Tezos Art Screen Saver")
        header.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        header.frame = NSRect(x: 20, y: 252, width: 380, height: 20)
        content.addSubview(header)

        let status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 20, y: 230, width: 380, height: 16)
        content.addSubview(status)
        self.statusLabel = status

        let sourceTitle = NSTextField(labelWithString: "Content Source:")
        sourceTitle.frame = NSRect(x: 20, y: 194, width: 120, height: 20)
        content.addSubview(sourceTitle)

        let srcPopup = NSPopUpButton(frame: NSRect(x: 145, y: 190, width: 255, height: 26), pullsDown: false)
        content.addSubview(srcPopup)
        self.sourcePopup = srcPopup

        let intervalTitle = NSTextField(labelWithString: "Rotation Interval:")
        intervalTitle.frame = NSRect(x: 20, y: 158, width: 120, height: 20)
        content.addSubview(intervalTitle)

        let popup = NSPopUpButton(frame: NSRect(x: 145, y: 154, width: 255, height: 26), pullsDown: false)
        popup.addItems(withTitles: [
            "Use desKTop App Setting",
            "Every 15 Seconds",
            "Every 30 Seconds",
            "Every 1 Minute",
            "Every 5 Minutes"
        ])
        content.addSubview(popup)
        self.intervalPopup = popup

        let shuffleCheck = NSButton(checkboxWithTitle: "Shuffle Artworks", target: nil, action: nil)
        shuffleCheck.frame = NSRect(x: 20, y: 122, width: 380, height: 22)
        content.addSubview(shuffleCheck)
        self.shuffleCheckbox = shuffleCheck

        let check = NSButton(checkboxWithTitle: "Show Artwork Museum Plaque", target: nil, action: nil)
        check.frame = NSRect(x: 20, y: 94, width: 380, height: 22)
        content.addSubview(check)
        self.plaqueCheckbox = check

        let fillCheck = NSButton(checkboxWithTitle: "Fill Screen (Crop to Fit Display)", target: nil, action: nil)
        fillCheck.frame = NSRect(x: 20, y: 66, width: 380, height: 22)
        content.addSubview(fillCheck)
        self.fillScreenCheckbox = fillCheck

        let openAppBtn = NSButton(title: "Open desKTop App…", target: self, action: #selector(openDesKTopApp(_:)))
        openAppBtn.bezelStyle = .rounded
        openAppBtn.frame = NSRect(x: 20, y: 18, width: 155, height: 30)
        content.addSubview(openAppBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelConfigureSheet(_:)))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.frame = NSRect(x: 230, y: 18, width: 80, height: 30)
        content.addSubview(cancelBtn)

        let okBtn = NSButton(title: "OK", target: self, action: #selector(saveAndCloseConfigureSheet(_:)))
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r"
        okBtn.frame = NSRect(x: 320, y: 18, width: 80, height: 30)
        content.addSubview(okBtn)

        panel.contentView = content
        self.configSheetPanel = panel
        loadManifest()
        syncConfigureSheetState()
        return panel
    }

    private func syncConfigureSheetState() {
        let defaults = saverDefaults

        // Populate source popup
        sourcePopup?.removeAllItems()
        sourcePopupIds = ["appDefault"]
        sourcePopup?.addItem(withTitle: "Use desKTop App Setting")
        let fallbackSources = [
            ManifestSource(id: "sameAsDesktop", name: "Same as Desktop Rotation"),
            ManifestSource(id: "favorites", name: "Favorites"),
            ManifestSource(id: "allLibrary", name: "Entire Library")
        ]
        let list = availableSources.isEmpty ? fallbackSources : availableSources
        for src in list {
            sourcePopupIds.append(src.id)
            sourcePopup?.addItem(withTitle: src.name)
        }
        let savedSource = defaults.string(forKey: Self.selectedSourceDefaultsKey) ?? "appDefault"
        if let idx = sourcePopupIds.firstIndex(of: savedSource) {
            sourcePopup?.selectItem(at: idx)
        } else {
            sourcePopup?.selectItem(at: 0)
        }

        let showPlaque = defaults.object(forKey: Self.showPlaqueDefaultsKey) as? Bool ?? true
        plaqueCheckbox?.state = showPlaque ? .on : .off

        let fillScreen = defaults.object(forKey: Self.fillScreenDefaultsKey) as? Bool ?? false
        fillScreenCheckbox?.state = fillScreen ? .on : .off

        let shuffleVal = defaults.object(forKey: Self.shuffleDefaultsKey) as? Bool ?? manifestShuffle
        shuffleCheckbox?.state = shuffleVal ? .on : .off

        let customInterval = defaults.double(forKey: Self.customIntervalDefaultsKey)
        let idx: Int
        switch Int(customInterval) {
        case 15: idx = 1
        case 30: idx = 2
        case 60: idx = 3
        case 300: idx = 4
        default: idx = 0
        }
        intervalPopup?.selectItem(at: idx)

        if allItems.isEmpty {
            statusLabel?.stringValue = "No synced artworks found yet — open desKTop to sync."
        } else {
            statusLabel?.stringValue = "\(items.count) artwork\(items.count == 1 ? "" : "s") in selected source (\(allItems.count) cached total)."
        }
    }

    @objc private func openDesKTopApp(_ sender: Any?) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "xyz.fafolab.desktop") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func cancelConfigureSheet(_ sender: Any?) {
        dismissSheet()
    }

    @objc private func saveAndCloseConfigureSheet(_ sender: Any?) {
        let defaults = saverDefaults
        if let srcPopup = sourcePopup {
            let selIdx = srcPopup.indexOfSelectedItem
            if selIdx >= 0 && selIdx < sourcePopupIds.count {
                defaults.set(sourcePopupIds[selIdx], forKey: Self.selectedSourceDefaultsKey)
            }
        }
        if let check = plaqueCheckbox {
            defaults.set(check.state == .on, forKey: Self.showPlaqueDefaultsKey)
        }
        if let fill = fillScreenCheckbox {
            defaults.set(fill.state == .on, forKey: Self.fillScreenDefaultsKey)
        }
        if let shuf = shuffleCheckbox {
            defaults.set(shuf.state == .on, forKey: Self.shuffleDefaultsKey)
        }
        if let popup = intervalPopup {
            let secs: Double
            switch popup.indexOfSelectedItem {
            case 1: secs = 15
            case 2: secs = 30
            case 3: secs = 60
            case 4: secs = 300
            default: secs = 0
            }
            defaults.set(secs, forKey: Self.customIntervalDefaultsKey)
        }
        defaults.synchronize()
        applySourceFilter(currentTokenId: nil)
        applyScalingPreference()
        updatePlaqueVisibility()
        displayCurrentItem()
        dismissSheet()
    }

    private func dismissSheet() {
        guard let panel = configSheetPanel else { return }
        panel.sheetParent?.endSheet(panel)
        panel.orderOut(nil)
    }

    private func effectiveIntervalSeconds() -> TimeInterval {
        let custom = saverDefaults.double(forKey: Self.customIntervalDefaultsKey)
        if custom > 0 { return custom }
        return manifestInterval > 0 ? manifestInterval : 300
    }

    private func effectiveShuffle() -> Bool {
        if let explicit = saverDefaults.object(forKey: Self.shuffleDefaultsKey) as? Bool {
            return explicit
        }
        return manifestShuffle
    }

    private func effectiveSourceId() -> String {
        let saved = saverDefaults.string(forKey: Self.selectedSourceDefaultsKey) ?? "appDefault"
        if saved == "appDefault" {
            return manifestDefaultSourceId
        }
        return saved
    }

    private func applyScalingPreference() {
        let fillScreen = saverDefaults.object(forKey: Self.fillScreenDefaultsKey) as? Bool ?? false
        imageView?.imageScaling = fillScreen ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        playerLayer?.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
    }

    private func loadManifest() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let manifestURL = appSupport
            .appendingPathComponent("desKTop", isDirectory: true)
            .appendingPathComponent("screensaver_manifest.json")

        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return }

        manifestInterval = manifest.intervalSeconds
        manifestDefaultSourceId = manifest.defaultSourceId ?? "sameAsDesktop"
        manifestShuffle = manifest.shuffle ?? false
        availableSources = manifest.sources ?? []
        allItems = manifest.items.filter { item in
            if let p = item.localMediaPath, FileManager.default.fileExists(atPath: p) { return true }
            if let f = item.fallbackImagePath, FileManager.default.fileExists(atPath: f) { return true }
            return false
        }

        applySourceFilter(currentTokenId: manifest.currentTokenId)
    }

    private func applySourceFilter(currentTokenId: String?) {
        let srcId = effectiveSourceId()
        let filtered: [ManifestItem]
        if srcId == "favorites" {
            filtered = allItems.filter { $0.isFavorite == true }
        } else if srcId == "allLibrary" {
            filtered = allItems
        } else if srcId.hasPrefix("gallery:") {
            let gid = String(srcId.dropFirst("gallery:".count))
            filtered = allItems.filter { ($0.galleryIds ?? []).contains(gid) }
        } else {
            let desktopOnly = allItems.filter { $0.isInDesktopRotation ?? true }
            filtered = desktopOnly.isEmpty ? allItems : desktopOnly
        }

        items = filtered.isEmpty ? allItems : filtered

        if let curId = currentTokenId,
           let idx = items.firstIndex(where: { $0.id == curId }) {
            currentIndex = idx
        } else if currentIndex >= items.count {
            currentIndex = 0
        }
    }

    private func clearVideo() {
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }

    private func displayCurrentItem() {
        lastRotationDate = Date()
        clearVideo()

        guard !items.isEmpty else {
            imageView?.isHidden = true
            titleLabel?.stringValue = "desKTop"
            subtitleLabel?.stringValue = "Open desKTop to sync your Tezos art library"
            updatePlaqueVisibility()
            return
        }

        let item = items[currentIndex % items.count]
        titleLabel?.stringValue = item.title
        let artistPart = item.artistDisplay.isEmpty ? "" : "by \(item.artistDisplay) • "
        subtitleLabel?.stringValue = "\(artistPart)\(item.marketplaceLabel) • #\(item.tokenId)"
        updatePlaqueVisibility()

        let mediaPath = item.localMediaPath
        let fallbackPath = item.fallbackImagePath
        let fillScreen = saverDefaults.object(forKey: Self.fillScreenDefaultsKey) as? Bool ?? false

        if item.category == "video", let path = mediaPath, FileManager.default.fileExists(atPath: path) {
            imageView?.isHidden = true
            let assetURL = URL(fileURLWithPath: path)
            let playerItem = AVPlayerItem(url: assetURL)
            let avPlayer = AVPlayer(playerItem: playerItem)
            avPlayer.isMuted = true
            avPlayer.actionAtItemEnd = .none

            let pLayer = AVPlayerLayer(player: avPlayer)
            pLayer.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
            pLayer.frame = bounds
            layer?.insertSublayer(pLayer, at: 0)

            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak avPlayer] _ in
                avPlayer?.seek(to: .zero)
                avPlayer?.play()
            }

            self.player = avPlayer
            self.playerLayer = pLayer
            avPlayer.play()
            return
        }

        let imagePathToLoad: String? = {
            if let p = mediaPath, FileManager.default.fileExists(atPath: p),
               let img = NSImage(contentsOfFile: p), img.isValid {
                return p
            }
            if let f = fallbackPath, FileManager.default.fileExists(atPath: f) {
                return f
            }
            return nil
        }()

        if let path = imagePathToLoad, let image = NSImage(contentsOfFile: path) {
            imageView?.image = image
            imageView?.imageScaling = fillScreen ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
            imageView?.isHidden = false
        } else {
            imageView?.isHidden = true
        }
    }

    private func updatePlaqueVisibility() {
        let showPlaque = saverDefaults.object(forKey: Self.showPlaqueDefaultsKey) as? Bool ?? true
        plaqueBox?.isHidden = !showPlaque
    }
}
