import SwiftUI

/// Menu bar drop-down content view for desKTop companion
public struct MenuBarContentView: View {
    @Binding public var currentToken: UnifiedToken?
    @Binding public var isPaused: Bool
    @Binding public var scaling: WallpaperScaling
    public let statusMessage: String
    public let onNext: () -> Void
    public let onPrevious: () -> Void
    public let onRestartAnimation: () -> Void
    public let onOpenLibrary: () -> Void

    public init(
        currentToken: Binding<UnifiedToken?>,
        isPaused: Binding<Bool>,
        scaling: Binding<WallpaperScaling>,
        statusMessage: String = "Active",
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onRestartAnimation: @escaping () -> Void,
        onOpenLibrary: @escaping () -> Void
    ) {
        self._currentToken = currentToken
        self._isPaused = isPaused
        self._scaling = scaling
        self.statusMessage = statusMessage
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onRestartAnimation = onRestartAnimation
        self.onOpenLibrary = onOpenLibrary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header / Current artwork info
            if let token = currentToken {
                VStack(alignment: .leading, spacing: 2) {
                    Text(token.name)
                        .font(.headline)
                        .lineLimit(1)

                    if !token.creators.isEmpty {
                        Text("by \(token.creators.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text(token.mediaCategory.rawValue.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)

                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
                .padding(.bottom, 4)

                Divider()
            }

            // Playback & Navigation Controls
            HStack(spacing: 12) {
                Button(action: onPrevious) {
                    Label("Prev", systemImage: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button(action: { isPaused.toggle() }) {
                    Label(isPaused ? "Play" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                }

                Button(action: onNext) {
                    Label("Next", systemImage: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Button(action: onRestartAnimation) {
                    Label("Replay", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            .buttonStyle(.borderless)

            Divider()

            // Framing mode switcher
            Picker("Framing", selection: $scaling) {
                Text("Fit (Ambient Blur)").tag(WallpaperScaling.fit)
                Text("Fill (Crop)").tag(WallpaperScaling.fill)
                Text("Center").tag(WallpaperScaling.center)
            }
            .pickerStyle(.menu)

            Divider()

            // Navigation links
            if let token = currentToken {
                Button(action: {
                    if let url = URL(string: "https://objkt.com/tokens/\(token.contract)/\(token.tokenId)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("View on objkt.com", systemImage: "arrow.up.right.square")
                }
            }

            Button(action: onOpenLibrary) {
                Label("Open Desktop Library...", systemImage: "photo.stack")
            }

            Divider()

            // About desKTop (Created by FAFOlab with strikethru, a FAFOlab joint)
            HStack(spacing: 4) {
                Text("desKTop")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link(destination: URL(string: "https://fafolab.xyz")!) {
                    HStack(spacing: 0) {
                        Text("FAFO")
                            .font(.caption)
                            .foregroundColor(.primary)
                        Text("lab")
                            .font(.caption)
                            .strikethrough()
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                Text("a FAFO~~lab~~ joint")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(minWidth: 260)
    }
}
