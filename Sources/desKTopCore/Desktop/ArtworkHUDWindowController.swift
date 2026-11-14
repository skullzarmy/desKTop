import AppKit
import SwiftUI

public enum HUDDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case transition = "transition"
    case always = "always"
    case off = "off"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .transition: return "Fade on Transition (5s)"
        case .always: return "Always Visible"
        case .off: return "Off"
        }
    }
}

private struct ArtworkHUDPlaqueView: View {
    let title: String
    let subtitle: String
    let badge: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.169, green: 0.447, blue: 1.0)) // Tezos Blue #2B72FF
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    if !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.65))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
    }
}

/// Manages subtle bottom-left Museum Plaque desktop overlays on each screen
@MainActor
public final class ArtworkHUDWindowController {
    public static let shared = ArtworkHUDWindowController()

    private var panels: [String: NSPanel] = [:]
    private var dismissTask: Task<Void, Never>?

    private init() {}

    public func show(
        token: UnifiedToken,
        artistDisplay: String,
        onScreens screens: [NSScreen]? = nil,
        mode: HUDDisplayMode,
        forcePeek: Bool = false
    ) {
        dismissTask?.cancel()

        if mode == .off && !forcePeek {
            hideAll()
            return
        }

        let targetScreens = screens ?? NSScreen.screens
        let subtitle = artistDisplay.isEmpty ? "" : "by \(artistDisplay)"
        let platformLabel = token.marketplace.shortName
        let badge = "\(platformLabel) • #\(token.tokenId)"

        var activeUUIDs = Set<String>()
        for screen in targetScreens {
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
            let uuid = DisplayManager.persistentUUID(for: screenID)
            activeUUIDs.insert(uuid)

            let panel = panels[uuid] ?? createPanel(for: screen)
            panels[uuid] = panel

            let plaque = ArtworkHUDPlaqueView(title: token.name, subtitle: subtitle, badge: badge)
            let hosting = NSHostingView(rootView: plaque)
            let fitting = hosting.fittingSize
            let clampedWidth = min(max(fitting.width, 180), min(440, screen.visibleFrame.width - 48))
            let height = fitting.height

            let origin = NSPoint(
                x: screen.visibleFrame.minX + 24,
                y: screen.visibleFrame.minY + 24
            )
            panel.contentView = hosting
            panel.setFrame(NSRect(x: origin.x, y: origin.y, width: clampedWidth, height: height), display: true)
            panel.alphaValue = 0
            panel.orderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                panel.animator().alphaValue = 1
            }
        }

        // Remove stale panels for disconnected screens
        for uuid in Array(panels.keys) where !activeUUIDs.contains(uuid) {
            panels[uuid]?.orderOut(nil)
            panels.removeValue(forKey: uuid)
        }

        if mode == .transition || forcePeek {
            dismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self?.fadeOutAll()
            }
        }
    }

    public func fadeOutAll() {
        dismissTask?.cancel()
        for panel in panels.values {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.45
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    if panel.alphaValue == 0 {
                        panel.orderOut(nil)
                    }
                }
            })
        }
    }

    public func hideAll() {
        dismissTask?.cancel()
        for panel in panels.values {
            panel.orderOut(nil)
            panel.alphaValue = 0
        }
    }

    private func createPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 2)
        panel.sharingType = .readOnly
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        return panel
    }
}
