import Foundation

/// Detected binary file format and verified MIME type
public enum SniffedMediaType: String, Sendable {
    case png = "image/png"
    case jpeg = "image/jpeg"
    case gif = "image/gif"
    case webp = "image/webp"
    case svg = "image/svg+xml"
    case mp4 = "video/mp4"
    case zipBundle = "application/zip"
    case html = "text/html"
    case gltfBinary = "model/gltf-binary"
    case unknown = "application/octet-stream"
}

/// Binary header sniffer verifying actual asset format regardless of server headers
public enum MediaTypeDetector {
    public static func detect(data: Data) -> SniffedMediaType {
        guard data.count >= 4 else { return .unknown }

        let bytes = [UInt8](data.prefix(32))

        // 1. PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes.count >= 8 &&
           bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
           bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A {
            return .png
        }

        // 2. JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .jpeg
        }

        // 3. GIF: 'GIF87a' or 'GIF89a' (47 49 46 38)
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return .gif
        }

        // 4. WebP: 'RIFF' .... 'WEBP'
        if bytes.count >= 12 &&
           bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return .webp
        }

        // 5. glTF Binary: 'glTF' (47 4C 54 46)
        if bytes[0] == 0x67 && bytes[1] == 0x6C && bytes[2] == 0x54 && bytes[3] == 0x46 {
            return .gltfBinary
        }

        // 6. ZIP Archive (used by fxhash, drop.art, Aleatory bundles): PK\x03\x04
        if bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04 {
            return .zipBundle
        }

        // 7. MP4 / MOV: bytes 4-7 are 'ftyp'
        if bytes.count >= 8 &&
           bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return .mp4
        }

        // 8. Text inspection for SVG and HTML in first 1024 bytes
        let inspectCount = min(data.count, 1024)
        if let prefixString = String(data: data.prefix(inspectCount), encoding: .utf8) ??
                              String(data: data.prefix(inspectCount), encoding: .ascii) {
            let lower = prefixString.lowercased()
            if lower.contains("<svg") {
                return .svg
            }
            if lower.contains("<!doctype html") || lower.contains("<html") {
                return .html
            }
        }

        return .unknown
    }
}
