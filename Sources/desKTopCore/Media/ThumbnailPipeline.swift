import AppKit
import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Lightweight actor managing download concurrency slots and in-flight task deduplication
private actor DownloadCoordinator {
    private let maxConcurrentDownloads = 6
    private var activeCount = 0

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var waiters: [Waiter] = []
    private var inFlightThumbnails: [String: Task<NSImage?, Never>] = [:]

    func acquireSlot() async -> Bool {
        if activeCount < maxConcurrentDownloads {
            activeCount += 1
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelWaiter(id: id)
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        if let idx = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: idx)
            waiter.continuation.resume(returning: false)
        }
    }

    func releaseSlot() {
        while !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
            return
        }
        activeCount = max(0, activeCount - 1)
    }

    func deduplicatedThumbnailTask(key: String, create: @Sendable () -> Task<NSImage?, Never>) -> Task<NSImage?, Never> {
        if let existing = inFlightThumbnails[key] {
            return existing
        }
        let task = create()
        inFlightThumbnails[key] = task
        return task
    }

    func clearInFlight(key: String) {
        inFlightThumbnails.removeValue(forKey: key)
    }
}

/// High-performance throttled thumbnail pipeline with parallel disk caching, in-flight coalescing,
/// gateway fallback, and cooperative concurrency limiting.
public final class ThumbnailPipeline: Sendable {
    public static let shared = ThumbnailPipeline()

    private let coordinator = DownloadCoordinator()
    private let diskCacheDirectory: URL
    private let session: URLSession

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheDirectory = caches.appendingPathComponent("desKTop/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.diskCacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 14.0
        config.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: config)
    }

    /// Hashes the URL to a unique disk cache file path
    private func diskCacheURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent("\(hex).jpg")
    }

    /// Reads and pre-decodes a cached JPEG from disk completely off the main thread & outside actor serialization
    private func readDiskThumbnail(at diskURL: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: diskURL.path),
              let source = CGImageSourceCreateWithURL(diskURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return nil
    }

    /// Returns candidate URLs for thumbnail download (primary URL + fast IPFS fallback if primary is fileship)
    private func candidateDownloadURLs(for url: URL) -> [URL] {
        var candidates = [url]
        let str = url.absoluteString
        if let range = str.range(of: "https://ipfs.fileship.xyz/") {
            let suffix = String(str[range.upperBound...])
            if let dweb = URL(string: "https://dweb.link/ipfs/\(suffix)") {
                candidates.append(dweb)
            }
        }
        return candidates
    }

    /// Loads a thumbnail image:
    /// 1. Instant lock-free in-memory cache
    /// 2. Parallel off-main-thread disk cache read (no actor serialization)
    /// 3. Deduplicated throttled network download (max 6 concurrent, cancellable, with fallback gateway)
    /// 4. Background downsampling to maxPixelSize and direct ImageIO JPEG write
    public func loadThumbnail(for url: URL, maxPixelSize: CGFloat = 360) async -> NSImage? {
        let nsURL = url as NSURL

        // 1. Instant in-memory cache hit
        if let cached = ImageMemoryCache.shared.object(forKey: nsURL) {
            return cached
        }

        // 2. Parallel off-actor disk cache read & decode
        let diskURL = diskCacheURL(for: url)
        let diskHit: NSImage? = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self, !Task.isCancelled else { return nil }
            return self.readDiskThumbnail(at: diskURL)
        }.value

        if let diskImage = diskHit {
            ImageMemoryCache.shared.setObject(diskImage, forKey: nsURL)
            return diskImage
        }

        if Task.isCancelled { return nil }

        // 3. Coalesce duplicate in-flight network requests for identical URLs
        let key = url.absoluteString
        let task = await coordinator.deduplicatedThumbnailTask(key: key) {
            Task.detached(priority: .utility) { [weak self] () -> NSImage? in
                guard let self = self else { return nil }
                defer {
                    Task { await self.coordinator.clearInFlight(key: key) }
                }

                guard await self.coordinator.acquireSlot() else { return nil }
                defer {
                    Task { await self.coordinator.releaseSlot() }
                }

                if Task.isCancelled { return nil }

                if let cached = ImageMemoryCache.shared.object(forKey: nsURL) {
                    return cached
                }
                if let diskImg = self.readDiskThumbnail(at: diskURL) {
                    ImageMemoryCache.shared.setObject(diskImg, forKey: nsURL)
                    return diskImg
                }

                for candidate in self.candidateDownloadURLs(for: url) {
                    if Task.isCancelled { return nil }
                    do {
                        var request = URLRequest(url: candidate)
                        request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")
                        request.timeoutInterval = 8.0

                        let (data, response) = try await self.session.data(for: request)
                        if Task.isCancelled { return nil }

                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                            continue
                        }

                        // Skip HTML/video/archive payloads so non-image responses don't waste decode cycles
                        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                        if contentType.contains("text/html") || contentType.contains("video/") || contentType.contains("audio/") || contentType.contains("application/zip") || contentType.contains("model/") {
                            return nil
                        }

                        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                            continue
                        }

                        let options: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceShouldCacheImmediately: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                        ]

                        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                            if let dest = CGImageDestinationCreateWithURL(diskURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                                CGImageDestinationAddImage(dest, cgThumb, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
                                CGImageDestinationFinalize(dest)
                            }
                            let img = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
                            ImageMemoryCache.shared.setObject(img, forKey: nsURL)
                            return img
                        } else if let img = NSImage(data: data) {
                            ImageMemoryCache.shared.setObject(img, forKey: nsURL)
                            return img
                        }
                    } catch {
                        continue
                    }
                }
                return nil
            }
        }

        return await task.value
    }

    /// Loads the full animated GIF data strictly when hovered (throttled, cancellable)
    public func loadAnimatedGIF(for url: URL) async -> NSImage? {
        let animKey = NSURL(string: url.absoluteString + "#animated")!
        if let cached = ImageMemoryCache.shared.object(forKey: animKey) {
            return cached
        }

        guard await coordinator.acquireSlot() else { return nil }
        defer {
            Task { await coordinator.releaseSlot() }
        }

        if Task.isCancelled { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 14.0
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let img = NSImage(data: data) else { return nil }
            ImageMemoryCache.shared.setObject(img, forKey: animKey)
            return img
        } catch {
            return nil
        }
    }
}
