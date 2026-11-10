import AppKit
import CoreImage
import Foundation
import ImageIO

/// Defines how desktop wallpaper letterboxing and borders are matted
public enum WallpaperMatteMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case dynamicArtwork = "Dynamic Artwork Color"
    case black = "Pitch Black"
    case charcoal = "Deep Charcoal"
    case slate = "Dark Slate"
    case white = "Pure White"
    case custom = "Custom Color"

    public var id: String { rawValue }
}

/// Extracts dominant/average colors from images and manages wallpaper matting
public enum ArtworkMatteEngine {
    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Resolves the appropriate matte background color for an artwork
    public static func resolveMatteColor(
        imageURL: URL?,
        mode: WallpaperMatteMode,
        customHex: String? = nil
    ) -> NSColor {
        switch mode {
        case .dynamicArtwork:
            if let url = imageURL, let dominant = extractDominantColor(from: url) {
                return dominant
            }
            return .black

        case .black:
            return .black

        case .charcoal:
            return NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)

        case .slate:
            return NSColor(srgbRed: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)

        case .white:
            return .white

        case .custom:
            if let hex = customHex, let color = colorFromHex(hex) {
                return color
            }
            return .black
        }
    }

    /// Extracts dominant background color by sampling a lightweight ImageIO thumbnail with CoreImage
    public static func extractDominantColor(from fileURL: URL) -> NSColor? {
        var resolvedCI: CIImage?

        // Fast ImageIO frame-0 64px thumbnail path (avoids decoding all frames of huge animated GIFs)
        if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: false
            ]
            if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                resolvedCI = CIImage(cgImage: cgThumb)
            }
        }

        if resolvedCI == nil,
           let image = NSImage(contentsOf: fileURL),
           let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData) {
            resolvedCI = CIImage(bitmapImageRep: rep)
        }

        guard let ciImage = resolvedCI else {
            return nil
        }

        // Use CIAreaAverage filter to compute average tone
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)

        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0

        // Subtly deepen brightness so contrast with desktop icons remains strong
        let deepenedR = max(0.0, r * 0.85)
        let deepenedG = max(0.0, g * 0.85)
        let deepenedB = max(0.0, b * 0.85)

        return NSColor(srgbRed: deepenedR, green: deepenedG, blue: deepenedB, alpha: 1.0)
    }

    public static func colorFromHex(_ hex: String) -> NSColor? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6, let val = UInt64(clean, radix: 16) else {
            return nil
        }
        let r = CGFloat((val & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((val & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(val & 0x0000FF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

extension NSColor {
    public var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = max(0, min(255, Int(rgb.redComponent * 255.0)))
        let g = max(0, min(255, Int(rgb.greenComponent * 255.0)))
        let b = max(0, min(255, Int(rgb.blueComponent * 255.0)))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
