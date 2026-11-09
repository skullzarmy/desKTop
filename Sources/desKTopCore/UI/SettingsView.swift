import SwiftUI
import ServiceManagement
import AppKit

public struct SettingsView: View {
    @AppStorage("disableAnimations") private var disableAnimations: Bool = false
    @AppStorage("pauseOnBattery") private var pauseOnBattery: Bool = false
    @AppStorage("muteVideoAudio") private var muteVideoAudio: Bool = true
    @AppStorage("wallpaperScaling") private var wallpaperScalingRaw: String = WallpaperScaling.fit.rawValue
    @AppStorage("wallpaperMatteMode") private var wallpaperMatteModeRaw: String = WallpaperMatteMode.dynamicArtwork.rawValue
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates: Bool = true

    @State private var launchAtLogin: Bool = false

    // Update checker state
    @State private var isCheckingForUpdates: Bool = false
    @State private var updateResult: UpdateCheckResult?
    @State private var installProgress: Double?
    @State private var installStatusText: String = ""
    @State private var updateErrorMessage: String?

    private let repository: WalletRepository
    private let updateService = UpdateService.shared

    public init(repository: WalletRepository) {
        self.repository = repository
    }

    public var body: some View {
        TabView {
            energyTab
                .tabItem { Label("Energy & Motion", systemImage: "bolt.fill") }

            framingTab
                .tabItem { Label("Framing", systemImage: "aspectratio.fill") }

            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 440)
        .onAppear {
            checkLaunchAtLoginStatus()
        }
    }

    // MARK: - Subviews

    private var energyTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("Dynamic Art & Energy Controls", systemImage: "bolt.fill")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $disableAnimations) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Static Art Mode (Freeze Animations)")
                                .fontWeight(.medium)
                            Text("Replaces animated GIFs, video loops, and generative code with high-res static poster images for 0.0% background GPU drain.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: disableAnimations) { _ in notifySettingsChanged() }

                    Divider()

                    Toggle(isOn: $pauseOnBattery) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause Animations on Battery Power")
                                .fontWeight(.medium)
                            Text("Automatically suspends dynamic canvas rendering when your Mac is unplugged, switching to static art to conserve battery.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: pauseOnBattery) { _ in notifySettingsChanged() }

                    Divider()

                    Toggle(isOn: $muteVideoAudio) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mute Video Artwork Audio")
                                .fontWeight(.medium)
                            Text("Keeps desktop video wallpaper silent while looping.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
            }

            GroupBox(label: Label("Power Guardian Live Status", systemImage: "gauge.with.needle.fill")) {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Power Source").font(.caption).foregroundColor(.secondary)
                        Text(PowerGuardian.shared.isOnBattery ? "Battery Power" : "AC Power Connected")
                            .font(.callout).fontWeight(.medium)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Low Power Mode").font(.caption).foregroundColor(.secondary)
                        Text(PowerGuardian.shared.isLowPowerModeEnabled ? "Active (Throttled)" : "Off")
                            .font(.callout).fontWeight(.medium)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Canvas Mode").font(.caption).foregroundColor(.secondary)
                        Text(effectiveCanvasMode)
                            .font(.callout).fontWeight(.medium)
                            .foregroundColor(effectiveCanvasMode == "Dynamic" ? .blue : .green)
                    }
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(18)
    }

    private var framingTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("Display & Framing", systemImage: "aspectratio.fill")) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default Framing Mode").fontWeight(.medium)
                        Picker("", selection: $wallpaperScalingRaw) {
                            Text("Aspect Fit (Letterbox with Matte)").tag(WallpaperScaling.fit.rawValue)
                            Text("Aspect Fill (Crop to Screen)").tag(WallpaperScaling.fill.rawValue)
                            Text("Center (1:1 Native Resolution)").tag(WallpaperScaling.center.rawValue)
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: wallpaperScalingRaw) { _ in notifySettingsChanged() }
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
                        .onChange(of: wallpaperMatteModeRaw) { _ in notifySettingsChanged() }
                    }
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(18)
    }

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("Software Updates", systemImage: "arrow.triangle.2.circlepath")) {
                VStack(alignment: .leading, spacing: 12) {
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

                    Divider()

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

            Spacer()
        }
        .padding(18)
    }

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

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox(label: Label("System Integration", systemImage: "macwindow")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch desKTop at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
                .padding(10)
            }

            GroupBox(label: Label("About desKTop", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                            .resizable()
                            .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("desKTop").font(.headline)
                            Text("Turn your Mac desktop into a living Tezos art gallery.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    Text("a FAFOlab joint\nOpen source software released into the public domain under The Unlicense.")
                        .font(.caption2).foregroundColor(.secondary)

                    HStack(spacing: 14) {
                        Button("Visit fafolab.xyz") {
                            if let url = URL(string: "https://fafolab.xyz") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        Button("Follow @fafo_lab on X") {
                            if let url = URL(string: "https://x.com/fafo_lab") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(18)
    }

    // MARK: - Actions

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: Notification.Name("didChangeUserSettings"), object: nil)
    }

    private var effectiveCanvasMode: String {
        if disableAnimations { return "Static (Frozen)" }
        if pauseOnBattery && PowerGuardian.shared.isOnBattery { return "Static (Battery Saver)" }
        if PowerGuardian.shared.isLowPowerModeEnabled { return "Static (Low Power Mode)" }
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
