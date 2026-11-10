import AppKit
import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// High-performance throttled thumbnail pipeline with persistent disk caching and cooperative concurrency limiting.
/// Strictly limits simultaneous network downloads to 4, decodes/downsamples frame 0 off the main thread with ImageIO,
/// caches lightweight JPEGs directly to disk without AppKit locks, and cancels off-screen tasks so the UI never locks down.
public actor ThumbnailPipeline {
    public static let shared = ThumbnailPipeline()

    private let maxConcurrentDownloads = 4
    private var activeCount = 0

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var waiters: [Waiter] = []

    private let diskCacheDirectory: URL
    private let session: URLSession

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheDirectory = caches.appendingPathComponent("desKTop/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.diskCacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12.0
        config.timeoutIntervalForResource = 20.0
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    /// Hashes the URL to a unique disk cache file path
    private func diskCacheURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent("\(hex).jpg")
    }

    /// Acquires a throttled download slot with task cancellation support
    private func acquireSlot() async -> Bool {
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

    /// Releases a download slot and wakes the next uncancelled waiting task
    private func releaseSlot() {
        while !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
            return
        }
        activeCount = max(0, activeCount - 1)
    }

    /// Loads a thumbnail image:
    /// 1. Fast in-memory cache
    /// 2. Local persistent disk cache (instant frame 0 decoded JPEG)
    /// 3. Throttled cooperative network download (max 4 concurrent, cancellable)
    /// 4. Background downsampling to maxPixelSize and direct ImageIO JPEG write
    public func loadThumbnail(for url: URL, maxPixelSize: CGFloat = 360) async -> NSImage? {
        let nsURL = url as NSURL

        // 1. In-memory cache hit
        if let cached = ImageMemoryCache.shared.object(forKey: nsURL) {
            return cached
        }

        // 2. Check local disk cache (instant, no slot needed)
        let diskURL = diskCacheURL(for: url)
        if FileManager.default.fileExists(atPath: diskURL.path),
           let diskData = try? Data(contentsOf: diskURL),
           let diskImage = NSImage(data: diskData) {
            ImageMemoryCache.shared.setObject(diskImage, forKey: nsURL)
            return diskImage
        }

        // 3. Acquire throttled concurrency slot
        guard await acquireSlot() else { return nil }
        defer { releaseSlot() }

        // Respect cancellation
        if Task.isCancelled { return nil }

        // Re-check memory and disk in case a queued task just finished this URL
        if let cached = ImageMemoryCache.shared.object(forKey: nsURL) {
            return cached
        }
        if FileManager.default.fileExists(atPath: diskURL.path),
           let diskData = try? Data(contentsOf: diskURL),
           let diskImage = NSImage(data: diskData) {
            ImageMemoryCache.shared.setObject(diskImage, forKey: nsURL)
            return diskImage
        }

        // 4. Download media
        do {
            var request = URLRequest(url: url)
            request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 12.0

            let (data, response) = try await session.data(for: request)

            if Task.isCancelled { return nil }

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            // Downsample and decode frame 0 off the main thread with pure ImageIO
            let targetSize = maxPixelSize
            let thumbnail: NSImage? = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    return NSImage(data: data)
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: targetSize
                ]
                if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    // Write directly to disk cache using ImageIO (no AppKit locks, zero main thread touch)
                    if let dest = CGImageDestinationCreateWithURL(diskURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, cgThumb, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
                        CGImageDestinationFinalize(dest)
                    }
                    return NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
                }
                return NSImage(data: data)
            }.value

            if let img = thumbnail {
                ImageMemoryCache.shared.setObject(img, forKey: nsURL)
                return img
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Loads the full animated GIF data strictly when hovered (throttled, cancellable)
    public func loadAnimatedGIF(for url: URL) async -> NSImage? {
        let animKey = NSURL(string: url.absoluteString + "#animated")!
        if let cached = ImageMemoryCache.shared.object(forKey: animKey) {
            return cached
        }

        guard await acquireSlot() else { return nil }
        defer { releaseSlot() }

        if Task.isCancelled { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15.0
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
