import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

public enum SnapshotError: Error {
    case invalidVideoAsset
    case frameCaptureFailed
    case imageEncodingFailed
}

/// Headless raster snapshot generator for Flat-by-Default wallpaper rendering
public enum StaticSnapshotGenerator {
    /// Generates a high-res raster PNG snapshot of a video file at the given timestamp
    public static func generateVideoSnapshot(from videoURL: URL, at time: CMTime = .zero, outputURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let cgImage: CGImage
        do {
            let (image, _) = try await generator.image(at: time)
            cgImage = image
        } catch {
            throw SnapshotError.frameCaptureFailed
        }

        // Write as PNG
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
            throw SnapshotError.imageEncodingFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SnapshotError.imageEncodingFailed
        }
    }
}
