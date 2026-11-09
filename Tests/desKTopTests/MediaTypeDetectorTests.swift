import Foundation
import desKTopCore

public struct MediaTypeDetectorTests {
    public static func run() throws {
        // 1. PNG
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]
        try assertEqual(MediaTypeDetector.detect(data: Data(pngBytes)), .png)

        // 2. JPEG
        let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
        try assertEqual(MediaTypeDetector.detect(data: Data(jpegBytes)), .jpeg)

        // 3. GIF
        let gifBytes: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
        try assertEqual(MediaTypeDetector.detect(data: Data(gifBytes)), .gif)

        // 4. WebP
        let webpBytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]
        try assertEqual(MediaTypeDetector.detect(data: Data(webpBytes)), .webp)

        // 5. ZIP bundle
        let zipBytes: [UInt8] = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]
        try assertEqual(MediaTypeDetector.detect(data: Data(zipBytes)), .zipBundle)

        // 6. SVG text
        let svgString = "<?xml version=\"1.0\"?><svg width=\"100\" height=\"100\"><rect/></svg>"
        try assertEqual(MediaTypeDetector.detect(data: Data(svgString.utf8)), .svg)

        // 7. HTML text
        let htmlString = "<!DOCTYPE html><html><head><title>Generative</title></head></html>"
        try assertEqual(MediaTypeDetector.detect(data: Data(htmlString.utf8)), .html)
    }
}
