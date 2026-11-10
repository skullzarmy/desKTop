import AppKit
import Foundation
import CryptoKit

/// High-performance throttled thumbnail pipeline with persistent disk caching and cooperative concurrency limiting.
/// Strictly limits simultaneous network downloads to 4, decodes/downsamples frame 0 off the main thread,
/// caches lightweight JPEGs to disk, and cancels off-screen tasks so the UI never locks down.
public actor ThumbnailPipeline {
    public static let shared = ThumbnailPipeline()

    private let maxConcurrentDownloads = 4
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private let diskCacheDirectory: URL
    private let session: URLSession

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheDirectory = caches.appendingPathComponent("desKTop/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.diskCacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    /// Hashes the URL to a unique disk cache file path
    private func diskCacheURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent("\(hex).jpg")
    }

    /// Acquires a throttled download slot (max 4 concurrent)
    private func acquireSlot() async {
        if activeCount < maxConcurrentDownloads {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases a download slot and wakes the next waiting task
    private func releaseSlot() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }

    /// Loads a thumbnail image:
    /// 1. Fast in-memory cache
    /// 2. Local persistent disk cache (instant frame 0 decoded JPEG)
    /// 3. Throttled cooperative network download (max 4 concurrent)
    /// 4. Background downsampling to maxPixelSize and atomic disk write
    public func loadThumbnail(for url: URL, maxPixelSize: CGFloat = 360) async -> NSImage? {
        let nsURL = url as NSURL

        // 1. In-memory cache hit
        if let cached = ImageMemoryCache.shared.object(forKey: nsURL) {
            return cached
        }

        // 2. Check local disk cache
        let diskURL = diskCacheURL(for: url)
        if FileManager.default.fileExists(atPath: diskURL.path),
           let diskData = try? Data(contentsOf: diskURL),
           let diskImage = NSImage(data: diskData) {
            ImageMemoryCache.shared.setObject(diskImage, forKey: nsURL)
            return diskImage
        }

        // 3. Acquire throttled concurrency slot
        await acquireSlot()
        defer { releaseSlot() }

        // Respect cancellation (e.g. view scrolled offscreen)
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

            let (data, response) = try await session.data(for: request)

            if Task.isCancelled { return nil }

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            // Downsample and decode frame 0 off the main thread
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
                    return NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
                }
                return NSImage(data: data)
            }.value

            if let img = thumbnail {
                ImageMemoryCache.shared.setObject(img, forKey: nsURL)

                // Persist downsampled JPEG to disk asynchronously
                Task.detached(priority: .background) {
                    if let tiff = img.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                        try? jpegData.write(to: diskURL, options: .atomic)
                    }
                }
                return img
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Loads the full animated GIF data strictly when hovered (throttled)
    public func loadAnimatedGIF(for url: URL) async -> NSImage? {
        let animKey = NSURL(string: url.absoluteString + "#animated")!
        if let cached = ImageMemoryCache.shared.object(forKey: animKey) {
            return cached
        }

        await acquireSlot()
        defer { releaseSlot() }

        if Task.isCancelled { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")
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
