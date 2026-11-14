import SwiftUI
import ServiceManagement
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case display = "Display"
    case screenSaver = "Screen Saver"
    case shortcuts = "Shortcuts"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .display: return "display"
        case .screenSaver: return "sparkles.tv"
        case .shortcuts: return "keyboard"
        }
    }
}

public enum MultiMonitorMode: String, CaseIterable, Identifiable, Sendable {
    case mirrored = "mirrored"
    case independent = "independent"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mirrored: return "Mirrored (Same Artwork on All Screens)"
        case .independent: return "Independent (Different Artwork per Screen)"
        }
    }
}

public struct SettingsView: View {
    @AppStorage("disableAnimations") private var disableAnimations: Bool = false
    @AppStorage("pauseOnBattery") private var pauseOnBattery: Bool = false
    @AppStorage("muteVideoAudio") private var muteVideoAudio: Bool = true
    @AppStorage("wallpaperScaling") private var wallpaperScalingRaw: String = WallpaperScaling.fit.rawValue
    @AppStorage("wallpaperMatteMode") private var wallpaperMatteModeRaw: String = WallpaperMatteMode.dynamicArtwork.rawValue
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates: Bool = true
    @AppStorage("hudDisplayMode") private var hudDisplayModeRaw: String = HUDDisplayMode.transition.rawValue
    @AppStorage("multiMonitorMode") private var multiMonitorModeRaw: String = MultiMonitorMode.mirrored.rawValue
    @AppStorage("screenSaverSourceId") private var screenSaverSourceId: String = "sameAsDesktop"
    @AppStorage("screenSaverShuffle") private var screenSaverShuffle: Bool = false
    @AppStorage("globalHotkeysEnabled") private var globalHotkeysEnabled: Bool = true
    @AppStorage(MediaVault.cacheLimitBytesKey) private var cacheLimitBytes: Int = CacheAllotmentOption.gb5.rawValue
    @AppStorage("hideFlashingHazards") private var hideFlashingHazards: Bool = false
    @AppStorage("hideAdultContent") private var hideAdultContent: Bool = false
    @AppStorage("hideFlaggedTokens") private var hideFlaggedTokens: Bool = false

    @State private var selectedTab: SettingsTab
    @State private var launchAtLogin: Bool = false
    @State private var desktopIconsHidden: Bool = DesktopIconsManager.isDesktopIconsHidden
    @State private var hiddenCount: Int = 0
    @State private var saverGalleries: [DesktopGallery] = []
    @State private var cacheSizeBytes: Int64 = 0
    @State private var isPurgingCache: Bool = false
    @State private var recordingHotkeyAction: HotkeyAction?
    @State private var hotkeyMonitor: Any?
    @State private var hotkeyRefreshID: UUID = UUID()
    @ObservedObject private var powerGuardian = PowerGuardian.shared

    // Update checker state
    @State private var isCheckingForUpdates: Bool = false
    @State private var updateResult: UpdateCheckResult?
    @State private var installProgress: Double?
    @State private var installStatusText: String = ""
    @State private var updateErrorMessage: String?

    private let repository: WalletRepository
    private let updateService = UpdateService.shared

    public init(repository: WalletRepository, initialTab: SettingsTab = .general) {
        self.repository = repository
        self._selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Prominent, non-collapsing top tab bar with full-height hit targets
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            selectedTab == tab
                                ? Color(NSColor.selectedContentBackgroundColor).opacity(0.18)
                                : Color.clear
                        )
                        .foregroundColor(
                            selectedTab == tab
                                ? Color(NSColor.labelColor)
                                : Color(NSColor.secondaryLabelColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedTab == tab ? Color(NSColor.separatorColor) : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .display:
                        displayTab
                    case .screenSaver:
                        screenSaverTab
                    case .shortcuts:
                        shortcutsTab
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Text("desKTop v\(updateService.currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NotificationCenter.default.post(name: Notification.Name("desKTop.openLibrary"), object: nil)
                }) {
                    Label("Open Gallery Window", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("o", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 680, height: 550)
        .onAppear {
            checkLaunchAtLoginStatus()
            desktopIconsHidden = DesktopIconsManager.isDesktopIconsHidden
            Task {
                hiddenCount = await repository.getBlacklist().count
                saverGalleries = await repository.getGalleries()
                cacheSizeBytes = await MediaVault().totalAllCachesSize()
            }
        }
    }

    // MARK: - 1. General (Startup, Updates, Storage, Hidden, About)

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("Startup & Software Updates", systemImage: "arrow.triangle.2.circlepath")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch desKTop at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Installed Version").font(.caption).foregroundColor(.secondary)
                            Text("v\(updateService.currentVersion)").font(.title3).fontWeight(.bold)
                        }

                        Spacer()

                        Button(action: checkForUpdates) {
                            if isCheckingForUpdates {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking...")
                                }
                            } else {
                                Label("Check Now", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(isCheckingForUpdates)
                    }

                    Toggle("Automatically check for updates on launch", isOn: $autoCheckUpdates)

                    if let result = updateResult {
                        Divider()
                        renderUpdateResult(result)
                    }

                    if let err = updateErrorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
                .padding(10)
            }

            GroupBox(label: Label("Storage & Media Cache", systemImage: "internaldrive")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cached Artworks & Thumbnails")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Used on disk: \(ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(isPurgingCache ? "Purging…" : "Purge Cache") {
                            isPurgingCache = true
                            Task {
                                let vault = MediaVault()
                                try? await vault.clearAllCaches()
                                ScreenSaverManifest.clearContainerMedia()
                                let updatedSize = await vault.totalAllCachesSize()
                                await MainActor.run {
                                    cacheSizeBytes = updatedSize
                                    isPurgingCache = false
                                }
                            }
                        }
                        .controlSize(.small)
                        .disabled(isPurgingCache || cacheSizeBytes == 0)
                    }

                    HStack {
                        Text("Cache Allotment (LRU Auto-Clean):")
                            .font(.caption)
                        Spacer()
                        Picker("", selection: $cacheLimitBytes) {
                            ForEach(CacheAllotmentOption.allCases) { option in
                                Text(option.displayName).tag(option.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .onChange(of: cacheLimitBytes) { _, newValue in
                            Task {
                                let vault = MediaVault()
                                await vault.enforceCacheLimit(maxBytes: Int64(newValue))
                                let updatedSize = await vault.totalAllCachesSize()
                                await MainActor.run {
                                    cacheSizeBytes = updatedSize
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }

            GroupBox(label: Label("Content & Accessibility Filters", systemImage: "exclamationmark.shield")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Hide Flashing / Photosensitivity Hazards", isOn: $hideFlashingHazards)
                        .onChange(of: hideFlashingHazards) { _, _ in
                            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
                        }

                    Toggle("Hide Adult / Mature Content (18+)", isOn: $hideAdultContent)
                        .onChange(of: hideAdultContent) { _, _ in
                            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
                        }

                    Toggle("Hide Moderation-Flagged Tokens", isOn: $hideFlaggedTokens)
                        .onChange(of: hideFlaggedTokens) { _, _ in
                            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
                        }

                    Text("Uses standardized Objkt accessibility, content rating, and moderation flags globally across Desktop, Gallery Mode, and Screen Saver.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            GroupBox(label: Label("Hidden Artworks", systemImage: "eye.slash")) {
                HStack {
                    Text("Hidden from Rotation: \(hiddenCount) piece\(hiddenCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Restore All Hidden") {
                        Task {
                            try? await repository.clearBlacklist()
                            hiddenCount = 0
                            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
                        }
                    }
                    .controlSize(.small)
                    .disabled(hiddenCount == 0)
                }
                .padding(10)
            }

            GroupBox(label: Label("About desKTop", systemImage: "info.circle")) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("desKTop — a FAFOlab joint").font(.subheadline).fontWeight(.semibold)
                        Text("Public domain software under The Unlicense. Zero keys, zero telemetry.")
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("fafolab.xyz") {
                        if let url = URL(string: "https://fafolab.xyz") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)

                    Button("@fafo_lab") {
                        if let url = URL(string: "https://x.com/fafo_lab") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(18)
    }

    // MARK: - 2. Display (Framing, Multi-Monitor, HUD, Energy & Motion)

    private var displayTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("Framing & Matte", systemImage: "aspectratio.fill")) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default Framing Mode").fontWeight(.medium)
                        Picker("", selection: $wallpaperScalingRaw) {
                            Text("Aspect Fit (Letterbox with Matte)").tag(WallpaperScaling.fit.rawValue)
                            Text("Aspect Fill (Crop to Screen)").tag(WallpaperScaling.fill.rawValue)
                            Text("Center (1:1 Native Resolution)").tag(WallpaperScaling.center.rawValue)
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: wallpaperScalingRaw) { _, _ in notifySettingsChanged() }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Letterbox Matte Color").fontWeight(.medium)
                        Picker("", selection: $wallpaperMatteModeRaw) {
                            Text("Dynamic Artwork Color (Ambient Palette)").tag(WallpaperMatteMode.dynamicArtwork.rawValue)
                            Text("Obsidian Black (#000000)").tag(WallpaperMatteMode.black.rawValue)
                            Text("Dark Slate (#1E1E26)").tag(WallpaperMatteMode.slate.rawValue)
                            Text("Clean White (#FFFFFF)").tag(WallpaperMatteMode.white.rawValue)
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: wallpaperMatteModeRaw) { _, _ in notifySettingsChanged() }
                    }
                }
                .padding(10)
            }

            GroupBox(label: Label("Desktop & Multi-Monitor", systemImage: "photo.artframe")) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Multi-Monitor Mode").fontWeight(.medium)
                        Picker("", selection: $multiMonitorModeRaw) {
                            ForEach(MultiMonitorMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: multiMonitorModeRaw) { _, _ in
                            NotificationCenter.default.post(name: Notification.Name("desKTop.didChangeDigitalFrameSettings"), object: nil)
                        }
                    }

                    Divider()

                    Toggle(isOn: $desktopIconsHidden) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clean Frame Mode (Hide Desktop Icons)")
                                .fontWeight(.medium)
                            Text("Temporarily hides Finder desktop icons so your screen reads like a pure digital art frame.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: desktopIconsHidden) { _, newValue in
                        DesktopIconsManager.setDesktopIconsHidden(newValue)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Artwork Plaque Overlay (Bottom-Left HUD)").fontWeight(.medium)
                            Spacer()
                            Button("Peek Plaque Now") {
                                NotificationCenter.default.post(name: Notification.Name("desKTop.peekHUD"), object: nil)
                            }
                            .controlSize(.small)
                        }
                        Picker("", selection: $hudDisplayModeRaw) {
                            ForEach(HUDDisplayMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: hudDisplayModeRaw) { _, _ in
                            NotificationCenter.default.post(name: Notification.Name("desKTop.didChangeDigitalFrameSettings"), object: nil)
                        }
                    }
                }
                .padding(10)
            }

            GroupBox(label: Label("Energy & Motion", systemImage: "bolt.fill")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $disableAnimations) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Freeze Dynamic Animations (Always Static)")
                                .fontWeight(.medium)
                            Text("Renders video, GIF, and generative WebGL/JS art as crisp, zero-CPU static snapshots.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: disableAnimations) { _, _ in notifySettingsChanged() }

                    Divider()

                    Toggle(isOn: $pauseOnBattery) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause Animations on Battery Power")
                                .fontWeight(.medium)
                            Text("Automatically pauses motion and switches to static snapshots when unplugged or in Low Power Mode.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: pauseOnBattery) { _, _ in notifySettingsChanged() }

                    Divider()

                    Toggle(isOn: $muteVideoAudio) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mute Video Artwork Audio")
                                .fontWeight(.medium)
                            Text("Prevents video wallpapers from playing soundtracks into desktop audio.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Power Source").font(.caption).foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: powerGuardian.isOnBattery ? "battery.50" : "powerplug.fill")
                                    .foregroundColor(powerGuardian.isOnBattery ? .orange : .green)
                                Text(powerGuardian.isOnBattery ? "Battery" : "AC Power")
                                    .font(.callout).fontWeight(.medium)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Low Power Mode").font(.caption).foregroundColor(.secondary)
                            Text(powerGuardian.isLowPowerModeEnabled ? "Active (Throttled)" : "Off")
                                .font(.callout).fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Canvas Mode").font(.caption).foregroundColor(.secondary)
                            Text(effectiveCanvasMode)
                                .font(.callout).fontWeight(.medium)
                                .foregroundColor(effectiveCanvasMode == "Dynamic" ? .blue : .green)
                        }
                    }
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(18)
    }

    // MARK: - 3. Screen Saver

    private var screenSaverTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("macOS System Screen Saver (desKTop.saver)", systemImage: "desktopcomputer")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System Screen Saver Plugin")
                                .fontWeight(.medium)
                            Text(ScreenSaverInstaller.isInstalled
                                 ? "Installed — open System Settings → Screen Saver and select desKTop under Other."
                                 : "Not yet installed in ~/Library/Screen Savers")
                                .font(.caption)
                                .foregroundColor(ScreenSaverInstaller.isInstalled ? .green : .secondary)
                        }
                        Spacer()
                        Button(ScreenSaverInstaller.isInstalled ? "Reinstall Plugin" : "Install Plugin") {
                            _ = try? ScreenSaverInstaller.installOrUpdate()
                            hotkeyRefreshID = UUID()
                        }
                        .controlSize(.small)
                        .help("Copy the bundled desKTop.saver plugin into ~/Library/Screen Savers")
                        Button("Open System Settings…") {
                            _ = try? ScreenSaverInstaller.installOrUpdate()
                            ScreenSaverInstaller.openSystemScreenSaverSettings()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(10)
            }

            GroupBox(label: Label("Screen Saver Content & Playback", systemImage: "photo.on.rectangle")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Screen Saver Content:")
                            .fontWeight(.medium)
                        Spacer()
                        Picker("", selection: $screenSaverSourceId) {
                            Text("Same as Desktop Rotation").tag("sameAsDesktop")
                            Text("Favorites").tag("favorites")
                            Text("Entire Library").tag("allLibrary")
                            if !saverGalleries.isEmpty {
                                Divider()
                                ForEach(saverGalleries) { gallery in
                                    Text("Gallery: \(gallery.name)").tag("gallery:\(gallery.id.uuidString)")
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                        .onChange(of: screenSaverSourceId) { _, _ in
                            NotificationCenter.default.post(name: Notification.Name("desKTop.didChangeScreenSaverSource"), object: nil)
                        }
                    }

                    Toggle("Shuffle Screen Saver Artworks", isOn: $screenSaverShuffle)
                        .onChange(of: screenSaverShuffle) { _, _ in
                            NotificationCenter.default.post(name: Notification.Name("desKTop.didChangeScreenSaverSource"), object: nil)
                        }

                    Text("Works via System Settings → Screen Saver even when desKTop is quit for cached images, GIFs, and videos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(18)
    }

    // MARK: - 4. Shortcuts

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("System-Wide Keyboard Shortcuts", systemImage: "keyboard")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("Enable Global Hotkeys", isOn: $globalHotkeysEnabled)
                            .fontWeight(.medium)
                            .onChange(of: globalHotkeysEnabled) { _, _ in
                                NotificationCenter.default.post(name: Notification.Name("desKTop.didChangeDigitalFrameSettings"), object: nil)
                            }
                        Spacer()
                        Button("Reset Defaults") {
                            stopRecordingHotkey()
                            GlobalHotkeyManager.shared.resetBindingsToDefaults()
                            hotkeyRefreshID = UUID()
                        }
                        .controlSize(.small)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(HotkeyAction.allCases, id: \.rawValue) { action in
                            let currentBinding = GlobalHotkeyManager.shared.binding(for: action)
                            let isRecording = recordingHotkeyAction == action
                            HStack(spacing: 8) {
                                Text(action.title)
                                    .font(.callout)
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: {
                                    if isRecording {
                                        stopRecordingHotkey()
                                    } else {
                                        startRecordingHotkey(for: action)
                                    }
                                }) {
                                    Text(isRecording ? "Press shortcut… (Esc cancels, ⌫ disables)" : currentBinding.displayString)
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.16))
                                        .foregroundColor(isRecording ? .accentColor : (currentBinding.isEnabled ? .primary : .secondary))
                                        .cornerRadius(5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Click and press a key combination with ⌘, ⌥, ⌃, or ⇧")
                            }
                        }
                    }
                    .id(hotkeyRefreshID)
                    .onDisappear {
                        stopRecordingHotkey()
                    }

                    Text("Uses native macOS Carbon hotkeys — no Accessibility permissions required.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(18)
    }

    // MARK: - Updates Helper

    @ViewBuilder
    private func renderUpdateResult(_ result: UpdateCheckResult) -> some View {
        switch result {
        case .updateAvailable(let newVer, let notes, let downloadURL, let pageURL):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles").foregroundColor(.yellow)
                    Text("Update Available: \(newVer)").fontWeight(.bold)
                }

                if let n = notes, !n.isEmpty {
                    ScrollView {
                        Text(n)
                            .font(.caption)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .frame(maxHeight: 80)
                }

                if let progress = installProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text(installStatusText).font(.caption2).foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button(action: { installUpdate(downloadURL: downloadURL) }) {
                            Label("Install & Restart", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("View Release Notes") {
                            NSWorkspace.shared.open(pageURL)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)

        case .upToDate(let ver):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("desKTop is up to date (version \(ver)).").font(.subheadline)
            }

        case .error(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("Update check failed: \(msg)").font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: Notification.Name("didChangeUserSettings"), object: nil)
    }

    private var effectiveCanvasMode: String {
        if disableAnimations { return "Static (Frozen)" }
        if pauseOnBattery && powerGuardian.isOnBattery { return "Static (Battery Saver)" }
        if powerGuardian.isLowPowerModeEnabled { return "Static (Low Power Mode)" }
        return "Dynamic"
    }

    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateErrorMessage = nil
        Task {
            let res = await updateService.checkForUpdates()
            await MainActor.run {
                self.updateResult = res
                self.isCheckingForUpdates = false
            }
        }
    }

    private func installUpdate(downloadURL: URL) {
        installProgress = 0.05
        installStatusText = "Downloading update..."
        updateErrorMessage = nil

        Task {
            do {
                try await updateService.downloadAndInstall(downloadURL: downloadURL) { progress, status in
                    Task { @MainActor in
                        self.installProgress = progress
                        self.installStatusText = status
                    }
                }
            } catch {
                await MainActor.run {
                    self.installProgress = nil
                    self.updateErrorMessage = "Install failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func startRecordingHotkey(for action: HotkeyAction) {
        stopRecordingHotkey()
        recordingHotkeyAction = action
        GlobalHotkeyManager.shared.setRecordingSuspended(true)

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = HotkeyBinding.carbonModifiers(from: event.modifierFlags)
            let keyCode = UInt32(event.keyCode)

            // Esc without modifiers cancels recording
            if event.keyCode == 53 && mods == 0 {
                stopRecordingHotkey()
                return nil
            }

            // Backspace / Delete without modifiers disables this shortcut
            if (event.keyCode == 51 || event.keyCode == 117) && mods == 0 {
                GlobalHotkeyManager.shared.setBinding(
                    HotkeyBinding(keyCode: action.keyCode, modifiers: action.modifiers, isEnabled: false),
                    for: action
                )
                hotkeyRefreshID = UUID()
                stopRecordingHotkey()
                return nil
            }

            // Require at least one modifier key (Cmd, Opt, Ctrl, Shift)
            guard mods != 0 else {
                return nil
            }

            GlobalHotkeyManager.shared.setBinding(
                HotkeyBinding(keyCode: keyCode, modifiers: mods, isEnabled: true),
                for: action
            )
            hotkeyRefreshID = UUID()
            stopRecordingHotkey()
            return nil
        }
    }

    private func stopRecordingHotkey() {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        recordingHotkeyAction = nil
        GlobalHotkeyManager.shared.setRecordingSuspended(false)
    }

    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
            }
        }
    }
}
