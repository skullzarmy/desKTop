import AppKit
import Foundation
import CoreGraphics
import CoreImage

public enum WallpaperScaling: String, Codable, Sendable {
    case fit = "Fit (Aspect Fit with Ambient Blur)"
    case fill = "Fill (Aspect Fill / Crop)"
    case center = "Center (Original Dimensions)"
}

public enum WallpaperError: Error {
    case screenNotFound
    case imageLoadFailed
    case renderFailed
    case systemWorkspaceError(Error)
}

/// Service managing macOS desktop wallpaper setting via NSWorkspace with screen-composited paths
public final class StillWallpaperService: Sendable {
    private let activeWallpaperDirectory: URL

    public init(activeDirectory: URL? = nil) {
        if let custom = activeDirectory {
            self.activeWallpaperDirectory = custom
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.activeWallpaperDirectory = caches.appendingPathComponent("desKTop/ActiveWallpapers", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.activeWallpaperDirectory, withIntermediateDirectories: true)
    }

    /// Prepares a cache-busted unique file URL for the token image (used for direct copying or testing)
    public func prepareCacheBustedURL(sourceURL: URL, tokenId: String) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let uniqueName = "wallpaper_\(tokenId)_\(timestamp).\(ext)"
        let targetURL = activeWallpaperDirectory.appendingPathComponent(uniqueName)

        // Copy source to unique destination
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)

        return targetURL
    }

    /// Prunes stale cached wallpapers to keep disk footprint minimal
    private func cleanOldWallpapers() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: activeWallpaperDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        if files.count > 10 {
            let sorted = files.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return d1 < d2
            }
            for file in sorted.prefix(files.count - 5) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Sets the desktop wallpaper for a specific screen (or all screens if nil), compositing to exact physical device dimensions
    /// so that .fill, .fit, and .center are guaranteed to work across all macOS versions regardless of
    /// deprecated NSWorkspace DesktopImageOptionKey behavior.
    @MainActor
    @discardableResult
    public func setDesktopWallpaper(
        imageURL: URL,
        tokenId: String,
        for targetScreen: NSScreen? = nil,
        scaling: WallpaperScaling = .fit,
        matteColor: NSColor? = nil
    ) throws -> URL {
        guard let sourceImage = NSImage(contentsOf: imageURL), sourceImage.isValid else {
            throw WallpaperError.imageLoadFailed
        }

        cleanOldWallpapers()

        let screensToUpdate = targetScreen.map { [$0] } ?? (NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens)
        guard !screensToUpdate.isEmpty else {
            throw WallpaperError.screenNotFound
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        var primaryTargetURL: URL?

        for (index, screen) in screensToUpdate.enumerated() {
            let uniqueName = "wallpaper_\(tokenId)_s\(index)_\(timestamp).png"
            let targetURL = activeWallpaperDirectory.appendingPathComponent(uniqueName)

            // Target pixel dimensions matching physical Retina display resolution
            let targetWidth = max(Int(screen.frame.width * screen.backingScaleFactor), 1)
            let targetHeight = max(Int(screen.frame.height * screen.backingScaleFactor), 1)

            // Get true native pixel dimensions of the source artwork
            var imageWidth = sourceImage.size.width
            var imageHeight = sourceImage.size.height
            for rep in sourceImage.representations {
                if rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
                    imageWidth = CGFloat(rep.pixelsWide)
                    imageHeight = CGFloat(rep.pixelsHigh)
                    break
                }
            }
            guard imageWidth > 0 && imageHeight > 0 else {
                throw WallpaperError.imageLoadFailed
            }

            // Calculate drawing rectangle based on chosen framing mode
            let drawRect: CGRect
            switch scaling {
            case .fill:
                // Aspect Fill: scale up so artwork completely covers the entire screen, cropping any overhang
                let scale = max(CGFloat(targetWidth) / imageWidth, CGFloat(targetHeight) / imageHeight)
                let drawW = imageWidth * scale
                let drawH = imageHeight * scale
                let drawX = (CGFloat(targetWidth) - drawW) / 2.0
                let drawY = (CGFloat(targetHeight) - drawH) / 2.0
                drawRect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)

            case .fit:
                // Aspect Fit: scale proportionally so entire artwork is visible, letterboxed with matteColor
                let scale = min(CGFloat(targetWidth) / imageWidth, CGFloat(targetHeight) / imageHeight)
                let drawW = imageWidth * scale
                let drawH = imageHeight * scale
                let drawX = (CGFloat(targetWidth) - drawW) / 2.0
                let drawY = (CGFloat(targetHeight) - drawH) / 2.0
                drawRect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)

            case .center:
                // Center: 1:1 native pixel rendering centered on the screen canvas
                let drawW = imageWidth
                let drawH = imageHeight
                let drawX = (CGFloat(targetWidth) - drawW) / 2.0
                let drawY = (CGFloat(targetHeight) - drawH) / 2.0
                drawRect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)
            }

            // Create bitmap context matching target display dimensions
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw WallpaperError.renderFailed
            }

            // 1. Fill background with matteColor (or black)
            let bgNSColor = matteColor?.usingColorSpace(.sRGB) ?? NSColor.black
            context.setFillColor(bgNSColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

            // 2. High-quality interpolation for artwork drawing
            context.interpolationQuality = .high
            if let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.draw(cgImage, in: drawRect)
            } else {
                NSGraphicsContext.saveGraphicsState()
                let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.current = nsContext
                sourceImage.draw(in: drawRect)
                NSGraphicsContext.restoreGraphicsState()
            }

            guard let compositedCGImage = context.makeImage() else {
                throw WallpaperError.renderFailed
            }

            let bitmapRep = NSBitmapImageRep(cgImage: compositedCGImage)
            // Ensure size reflects point dimensions so macOS recognizes Retina DPI
            bitmapRep.size = screen.frame.size
            guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                throw WallpaperError.renderFailed
            }

            try pngData.write(to: targetURL, options: .atomic)

            let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                .allowClipping: true
            ]

            do {
                try NSWorkspace.shared.setDesktopImageURL(targetURL, for: screen, options: options)
                if primaryTargetURL == nil {
                    primaryTargetURL = targetURL
                }
            } catch {
                throw WallpaperError.systemWorkspaceError(error)
            }
        }

        return primaryTargetURL!
    }
}
