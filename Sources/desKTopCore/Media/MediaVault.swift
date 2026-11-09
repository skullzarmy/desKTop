import Foundation
import CryptoKit

/// Local content-addressed media cache vault
public actor MediaVault {
    private let cacheDirectory: URL
    private let gatewayManager: IPFSGatewayManager

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

    /// Checks if a URI is already cached locally, returning the file URL if present
    public func localCachedURL(for uriString: String) -> URL? {
        let key = Self.cacheKey(for: uriString)
        let candidate = cacheDirectory.appendingPathComponent(key)

        // Check if file exists directly or with extension
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        // Check with extension
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            if let matched = files.first(where: { $0.deletingPathExtension().lastPathComponent == key }) {
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

        return (targetURL, detected)
    }

    /// Returns the total disk usage of cached media in bytes
    public func totalCacheSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for f in files {
            if let attrs = try? f.resourceValues(forKeys: [.fileSizeKey]), let size = attrs.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Clears the entire local media cache
    public func clearCache() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }
}
