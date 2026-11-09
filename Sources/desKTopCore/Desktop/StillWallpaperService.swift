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

/// Service managing macOS desktop wallpaper setting via NSWorkspace with cache-busting paths
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

    /// Prepares a cache-busted unique file URL for the token image
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

    /// Sets the desktop wallpaper for a specific screen
    @MainActor
    public func setDesktopWallpaper(
        imageURL: URL,
        tokenId: String,
        for screen: NSScreen,
        scaling: WallpaperScaling = .fit,
        matteColor: NSColor? = nil
    ) throws -> URL {
        let targetURL = try prepareCacheBustedURL(sourceURL: imageURL, tokenId: tokenId)

        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]

        switch scaling {
        case .fit:
            options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
            options[.allowClipping] = false
            if let color = matteColor {
                options[.fillColor] = color
            }
        case .fill:
            options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
            options[.allowClipping] = true
        case .center:
            options[.imageScaling] = NSImageScaling.scaleNone.rawValue
            options[.allowClipping] = false
            if let color = matteColor {
                options[.fillColor] = color
            }
        }

        do {
            try NSWorkspace.shared.setDesktopImageURL(targetURL, for: screen, options: options)
            return targetURL
        } catch {
            throw WallpaperError.systemWorkspaceError(error)
        }
    }
}
