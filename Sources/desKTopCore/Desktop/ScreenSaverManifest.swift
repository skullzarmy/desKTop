import AppKit
import Foundation

public struct ScreenSaverSourceOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ScreenSaverManifestItem: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artistDisplay: String
    public let marketplaceLabel: String
    public let tokenId: String
    public let category: String
    public let localMediaPath: String?
    public let fallbackImagePath: String?
    public let isInDesktopRotation: Bool
    public let isFavorite: Bool
    public let galleryIds: [String]

    public init(
        id: String,
        title: String,
        artistDisplay: String,
        marketplaceLabel: String,
        tokenId: String,
        category: String,
        localMediaPath: String?,
        fallbackImagePath: String?,
        isInDesktopRotation: Bool = true,
        isFavorite: Bool = false,
        galleryIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.artistDisplay = artistDisplay
        self.marketplaceLabel = marketplaceLabel
        self.tokenId = tokenId
        self.category = category
        self.localMediaPath = localMediaPath
        self.fallbackImagePath = fallbackImagePath
        self.isInDesktopRotation = isInDesktopRotation
        self.isFavorite = isFavorite
        self.galleryIds = galleryIds
    }
}

public struct ScreenSaverManifest: Codable, Equatable, Sendable {
    public let updatedAt: Date
    public let currentTokenId: String?
    public let intervalSeconds: Double
    public let defaultSourceId: String
    public let shuffle: Bool
    public let sources: [ScreenSaverSourceOption]
    public let items: [ScreenSaverManifestItem]

    public init(
        updatedAt: Date,
        currentTokenId: String?,
        intervalSeconds: Double,
        defaultSourceId: String = "sameAsDesktop",
        shuffle: Bool = false,
        sources: [ScreenSaverSourceOption] = [],
        items: [ScreenSaverManifestItem]
    ) {
        self.updatedAt = updatedAt
        self.currentTokenId = currentTokenId
        self.intervalSeconds = intervalSeconds
        self.defaultSourceId = defaultSourceId
        self.shuffle = shuffle
        self.sources = sources
        self.items = items
    }

    public static var manifestURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("desKTop", isDirectory: true)
            .appendingPathComponent("screensaver_manifest.json")
    }

    public static func write(_ manifest: ScreenSaverManifest) {
        let url = manifestURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }

        mirrorToScreenSaverContainers(manifest, encoder: encoder)
    }

    public static func syncExistingToContainers() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(ScreenSaverManifest.self, from: data) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        mirrorToScreenSaverContainers(manifest, encoder: encoder)
    }

    public static func clearContainerMedia() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let containerIds = [
            "com.apple.ScreenSaver.Engine.legacyScreenSaver",
            "com.apple.ScreenSaver.Engine.legacyScreenSaver.x86-64",
            "com.apple.ScreenSaver-Settings.extension"
        ]
        for cid in containerIds {
            let mediaDir = home
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(cid, isDirectory: true)
                .appendingPathComponent("Data/Library/Application Support/desKTop/media", isDirectory: true)
            if let files = try? fm.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil) {
                for f in files {
                    try? fm.removeItem(at: f)
                }
            }
        }
    }

    /// Apple's `legacyScreenSaver` runs inside an App Sandbox whose `Application Support`
    /// directory lives inside `~/Library/Containers/<bundle-id>/Data/Library/Application Support/`.
    /// Mirror the manifest and hardlink cached media into those containers so the native `.saver`
    /// bundle has full sandbox read access.
    private static func mirrorToScreenSaverContainers(_ manifest: ScreenSaverManifest, encoder: JSONEncoder) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let containerIds = [
            "com.apple.ScreenSaver.Engine.legacyScreenSaver",
            "com.apple.ScreenSaver.Engine.legacyScreenSaver.x86-64",
            "com.apple.ScreenSaver-Settings.extension"
        ]

        for cid in containerIds {
            let containerRoot = home
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(cid, isDirectory: true)
            guard fm.fileExists(atPath: containerRoot.path) else { continue }

            let appSupportDir = containerRoot
                .appendingPathComponent("Data/Library/Application Support/desKTop", isDirectory: true)
            let mediaDir = appSupportDir.appendingPathComponent("media", isDirectory: true)
            try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)

            func mirrorFile(_ sourcePath: String?, suffix: String) -> String? {
                guard let sourcePath, fm.fileExists(atPath: sourcePath) else { return nil }
                let sourceURL = URL(fileURLWithPath: sourcePath)
                let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
                let safeBase = sourceURL.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "/", with: "_")
                let destURL = mediaDir.appendingPathComponent("\(safeBase)\(suffix).\(ext)")
                if !fm.fileExists(atPath: destURL.path) {
                    if (try? fm.linkItem(at: sourceURL, to: destURL)) == nil {
                        try? fm.copyItem(at: sourceURL, to: destURL)
                    }
                }
                return fm.fileExists(atPath: destURL.path) ? destURL.path : nil
            }

            let mirroredItems = manifest.items.map { item in
                ScreenSaverManifestItem(
                    id: item.id,
                    title: item.title,
                    artistDisplay: item.artistDisplay,
                    marketplaceLabel: item.marketplaceLabel,
                    tokenId: item.tokenId,
                    category: item.category,
                    localMediaPath: mirrorFile(item.localMediaPath, suffix: ""),
                    fallbackImagePath: mirrorFile(item.fallbackImagePath, suffix: "_thumb"),
                    isInDesktopRotation: item.isInDesktopRotation,
                    isFavorite: item.isFavorite,
                    galleryIds: item.galleryIds
                )
            }

            let containerManifest = ScreenSaverManifest(
                updatedAt: manifest.updatedAt,
                currentTokenId: manifest.currentTokenId,
                intervalSeconds: manifest.intervalSeconds,
                defaultSourceId: manifest.defaultSourceId,
                shuffle: manifest.shuffle,
                sources: manifest.sources,
                items: mirroredItems
            )
            let destManifestURL = appSupportDir.appendingPathComponent("screensaver_manifest.json")
            if let data = try? encoder.encode(containerManifest) {
                try? data.write(to: destManifestURL, options: .atomic)
            }
        }
    }
}

@MainActor
public enum ScreenSaverInstaller {
    public static var userScreenSaversDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Screen Savers", isDirectory: true)
    }

    public static var installedSaverURL: URL {
        userScreenSaversDirectory.appendingPathComponent("desKTop.saver", isDirectory: true)
    }

    public static var bundledSaverURL: URL? {
        let embedded = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("ScreenSavers", isDirectory: true)
            .appendingPathComponent("desKTop.saver", isDirectory: true)
        if FileManager.default.fileExists(atPath: embedded.path) {
            return embedded
        }
        return nil
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedSaverURL.path)
    }

    @discardableResult
    public static func installOrUpdate() throws -> URL {
        guard let source = bundledSaverURL else {
            throw NSError(
                domain: "desKTop.ScreenSaverInstaller",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Embedded desKTop.saver bundle not found in app bundle."]
            )
        }

        let fm = FileManager.default
        try fm.createDirectory(at: userScreenSaversDirectory, withIntermediateDirectories: true)
        let dest = installedSaverURL
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
        return dest
    }

    public static func openSystemScreenSaverSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.desktopscreeneffect") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
