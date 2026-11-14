import SwiftUI

/// Menu bar drop-down content view for desKTop companion
public struct MenuBarContentView: View {
    @Binding public var currentToken: UnifiedToken?
    @Binding public var isPaused: Bool
    @Binding public var scaling: WallpaperScaling
    public let statusMessage: String
    public let isFavorite: Bool
    public let isInteractive: Bool
    public let isDesktopIconsHidden: Bool
    public let lastHiddenTokenName: String?
    public let onNext: () -> Void
    public let onPrevious: () -> Void
    public let onRestartAnimation: () -> Void
    public let onToggleFavorite: () -> Void
    public let onHideToken: () -> Void
    public let onUndoLastHide: () -> Void
    public let onToggleInteractive: () -> Void
    public let onToggleDesktopIcons: () -> Void
    public let onEnterGalleryMode: () -> Void
    public let onSaveToDownloads: () -> Void
    public let onCopyObjktLink: () -> Void
    public let onOpenLibrary: () -> Void
    public let onOpenSettings: () -> Void

    public init(
        currentToken: Binding<UnifiedToken?>,
        isPaused: Binding<Bool>,
        scaling: Binding<WallpaperScaling>,
        statusMessage: String = "Active",
        isFavorite: Bool = false,
        isInteractive: Bool = false,
        isDesktopIconsHidden: Bool = false,
        lastHiddenTokenName: String? = nil,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onRestartAnimation: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void = {},
        onHideToken: @escaping () -> Void = {},
        onUndoLastHide: @escaping () -> Void = {},
        onToggleInteractive: @escaping () -> Void = {},
        onToggleDesktopIcons: @escaping () -> Void = {},
        onEnterGalleryMode: @escaping () -> Void = {},
        onSaveToDownloads: @escaping () -> Void = {},
        onCopyObjktLink: @escaping () -> Void = {},
        onOpenLibrary: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self._currentToken = currentToken
        self._isPaused = isPaused
        self._scaling = scaling
        self.statusMessage = statusMessage
        self.isFavorite = isFavorite
        self.isInteractive = isInteractive
        self.isDesktopIconsHidden = isDesktopIconsHidden
        self.lastHiddenTokenName = lastHiddenTokenName
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onRestartAnimation = onRestartAnimation
        self.onToggleFavorite = onToggleFavorite
        self.onHideToken = onHideToken
        self.onUndoLastHide = onUndoLastHide
        self.onToggleInteractive = onToggleInteractive
        self.onToggleDesktopIcons = onToggleDesktopIcons
        self.onEnterGalleryMode = onEnterGalleryMode
        self.onSaveToDownloads = onSaveToDownloads
        self.onCopyObjktLink = onCopyObjktLink
        self.onOpenLibrary = onOpenLibrary
        self.onOpenSettings = onOpenSettings
    }

    private var canInteract: Bool {
        guard let cat = currentToken?.mediaCategory else { return false }
        return cat == .fxhash || cat == .aleatory || cat == .bootloader || cat == .editArt || cat == .interactiveHtml
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header / Current artwork info
            if let token = currentToken {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(token.name)
                            .font(.headline)
                            .lineLimit(1)

                        Spacer()

                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundColor(isFavorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

                        Button(action: onHideToken) {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Hide this piece from rotation")
                    }

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
                            .lineLimit(1)
                    }
                    .padding(.top, 2)

                    if let hiddenName = lastHiddenTokenName {
                        HStack(spacing: 6) {
                            Text("Hid “\(hiddenName)”")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Unhide") {
                                onUndoLastHide()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                            .foregroundColor(.blue)
                        }
                        .padding(.top, 4)
                    }
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

            // Digital Frame quick toggles
            VStack(alignment: .leading, spacing: 6) {
                if canInteract {
                    Button(action: onToggleInteractive) {
                        Label(
                            isInteractive ? "Exit Interactive Canvas (Esc)" : "Interact with Canvas",
                            systemImage: isInteractive ? "hand.tap.fill" : "hand.tap"
                        )
                    }
                    .foregroundColor(isInteractive ? .blue : .primary)
                }

                Button(action: onToggleDesktopIcons) {
                    Label(
                        isDesktopIconsHidden ? "Show Desktop Icons" : "Hide Desktop Icons (Clean Frame)",
                        systemImage: isDesktopIconsHidden ? "eye" : "rectangle.dashed"
                    )
                }

                Button(action: onEnterGalleryMode) {
                    Label("Enter Gallery Mode", systemImage: "photo.artframe")
                }
            }
            .buttonStyle(.borderless)

            Divider()

            // Navigation & collector links
            if let token = currentToken {
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: {
                        if let url = token.marketplaceTokenURL {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Label("View on \(token.marketplace.displayName)", systemImage: "arrow.up.right.square")
                    }

                    HStack(spacing: 14) {
                        Button(action: onCopyObjktLink) {
                            Label("Copy Link", systemImage: "link")
                        }

                        Button(action: onSaveToDownloads) {
                            Label("Save Artwork", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                .buttonStyle(.borderless)

                Divider()
            }

            VStack(alignment: .leading, spacing: 6) {
                Button(action: onOpenLibrary) {
                    Label("Open Desktop Library...", systemImage: "photo.stack")
                }

                Button(action: onOpenSettings) {
                    Label("Settings...", systemImage: "gearshape")
                }

                Button(action: { NSApp.terminate(nil) }) {
                    Label("Quit desKTop", systemImage: "power")
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless)

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
        .frame(minWidth: 280)
    }
}
