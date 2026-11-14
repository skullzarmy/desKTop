import Foundation
import CryptoKit

public enum CacheAllotmentOption: Int, CaseIterable, Identifiable, Sendable {
    case gb1 = 1_073_741_824
    case gb2 = 2_147_483_648
    case gb5 = 5_368_709_120
    case gb10 = 10_737_418_240
    case unlimited = 0

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .gb1: return "1 GB"
        case .gb2: return "2 GB"
        case .gb5: return "5 GB (Default)"
        case .gb10: return "10 GB"
        case .unlimited: return "Unlimited"
        }
    }
}

/// Local content-addressed media cache vault with automatic LRU garbage collection
public actor MediaVault {
    public static let cacheLimitBytesKey = "mediaCacheLimitBytes"
    public static let defaultLimitBytes: Int64 = Int64(CacheAllotmentOption.gb5.rawValue)

    private let cacheDirectory: URL
    private let gatewayManager: IPFSGatewayManager

    public static func configuredLimitBytes() -> Int64 {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: cacheLimitBytesKey) == nil {
            return defaultLimitBytes
        }
        return Int64(defaults.integer(forKey: cacheLimitBytesKey))
    }

    public init(
        cacheDirectory: URL? = nil,
        gatewayManager: IPFSGatewayManager = IPFSGatewayManager()
    ) {
        if let customDir = cacheDirectory {
            self.cacheDirectory = customDir
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.cacheDirectory = caches.appendingPathComponent("desKTop/MediaVault", isDirectory: true)
        }
        self.gatewayManager = gatewayManager

        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Generates content hash key for a given URI string
    public static func cacheKey(for uriString: String) -> String {
        let hash = SHA256.hash(data: Data(uriString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func touchFile(at url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    /// Checks if a URI is already cached locally, returning the file URL if present
    public func localCachedURL(for uriString: String) -> URL? {
        let key = Self.cacheKey(for: uriString)
        let candidate = cacheDirectory.appendingPathComponent(key)

        // Check if file exists directly or with extension
        if FileManager.default.fileExists(atPath: candidate.path) {
            touchFile(at: candidate)
            return candidate
        }

        // Check with extension
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            if let matched = files.first(where: { $0.deletingPathExtension().lastPathComponent == key }) {
                touchFile(at: matched)
                return matched
            }
        }

        return nil
    }

    /// Fetches and caches media for a given URI string, returning the local cached file URL and detected media type
    public func getOrFetchMedia(for uriString: String) async throws -> (fileURL: URL, mediaType: SniffedMediaType) {
        // 1. Check local cache hit
        if let cached = localCachedURL(for: uriString) {
            if let data = try? Data(contentsOf: cached) {
                let detected = MediaTypeDetector.detect(data: data)
                return (cached, detected)
            }
        }

        // 2. Fetch through gateway manager
        let (data, _) = try await gatewayManager.fetchData(from: uriString)
        let detected = MediaTypeDetector.detect(data: data)

        // 3. Determine file extension based on sniffed type
        let ext: String = {
            switch detected {
            case .png: return "png"
            case .jpeg: return "jpg"
            case .gif: return "gif"
            case .webp: return "webp"
            case .svg: return "svg"
            case .mp4: return "mp4"
            case .zipBundle: return "zip"
            case .html: return "html"
            case .gltfBinary: return "glb"
            case .unknown: return "bin"
            }
        }()

        let key = Self.cacheKey(for: uriString)
        let targetURL = cacheDirectory.appendingPathComponent("\(key).\(ext)")

        // Atomic write
        try data.write(to: targetURL, options: .atomic)
        enforceCacheLimit()

        return (targetURL, detected)
    }

    /// Evicts least-recently-used files from MediaVault when total size exceeds `maxBytes` (0 = unlimited).
    /// Also prunes stale wallpaper snapshots in `ActiveWallpapers`.
    @discardableResult
    public func enforceCacheLimit(maxBytes: Int64? = nil) -> Int {
        pruneActiveWallpapers(keepCount: 10)

        let limit = maxBytes ?? Self.configuredLimitBytes()
        guard limit > 0 else { return 0 }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys) else {
            return 0
        }

        struct CachedEntry {
            let url: URL
            let size: Int64
            let modified: Date
        }

        var entries: [CachedEntry] = []
        var total: Int64 = 0

        for f in files {
            guard let vals = try? f.resourceValues(forKeys: Set(keys)),
                  vals.isRegularFile == true,
                  let size = vals.fileSize else { continue }
            let int64Size = Int64(size)
            total += int64Size
            entries.append(CachedEntry(
                url: f,
                size: int64Size,
                modified: vals.contentModificationDate ?? .distantPast
            ))
        }

        guard total > limit else { return 0 }

        // Oldest modification date first (LRU)
        entries.sort { $0.modified < $1.modified }

        var evicted = 0
        for entry in entries {
            guard total > limit else { break }
            if (try? FileManager.default.removeItem(at: entry.url)) != nil {
                total -= entry.size
                evicted += 1
            }
        }
        return evicted
    }

    private func pruneActiveWallpapers(keepCount: Int) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let activeDir = caches.appendingPathComponent("desKTop/ActiveWallpapers", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: activeDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > keepCount else { return }

        let sorted = files.sorted { a, b in
            let dA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return dA > dB
        }
        for stale in sorted.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// Returns the total disk usage of MediaVault cached media in bytes
    public func totalCacheSize() -> Int64 {
        Self.directorySize(at: cacheDirectory)
    }

    /// Returns the total disk usage across all desKTop caches (MediaVault, ActiveWallpapers, Thumbnails)
    public func totalAllCachesSize() -> Int64 {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let root = caches.appendingPathComponent("desKTop", isDirectory: true)
        return max(Self.directorySize(at: root), Self.directorySize(at: cacheDirectory))
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               vals.isRegularFile == true,
               let size = vals.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Clears the MediaVault cache
    public func clearCache() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Purges all desKTop caches (MediaVault, ActiveWallpapers, Thumbnails)
    public func clearAllCaches() throws {
        try clearCache()
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let root = caches.appendingPathComponent("desKTop", isDirectory: true)
        if let subdirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for item in subdirs {
                if let children = try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    for child in children {
                        try? FileManager.default.removeItem(at: child)
                    }
                }
            }
        }
    }
}
