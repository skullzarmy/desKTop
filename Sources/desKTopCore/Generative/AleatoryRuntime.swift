import Foundation
import Compression

public enum DecompressionError: Error {
    case invalidEncoding
    case decompressionFailed
}

/// Runtime engine for Aleatory on-chain generative art pieces (ALEATORY-001)
public enum AleatoryRuntime {
    /// Multi-format decompressor supporting plain UTF-8, base64, and base64-deflate
    public static func decompress(code: String, encoding: String? = nil) throws -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. If explicit raw or contains javascript keyword, return as-is
        if encoding == "raw" || trimmed.contains("function") || trimmed.contains("const ") || trimmed.contains("let ") {
            return trimmed
        }

        // 2. Attempt Base64 decoding
        guard let base64Data = Data(base64Encoded: trimmed) else {
            // If not valid base64, treat as raw code
            return trimmed
        }

        // Check if raw UTF-8 was just base64 encoded
        if let utf8String = String(data: base64Data, encoding: .utf8),
           (utf8String.contains("function") || utf8String.contains("const ") || utf8String.contains("var ")) {
            return utf8String
        }

        // 3. Decompress zlib / deflate stream
        if let decompressed = decompressDeflate(data: base64Data) {
            if let result = String(data: decompressed, encoding: .utf8) {
                return result
            }
        }

        // Fallback to UTF-8 from base64 if decompression was not needed
        if let utf8Fallback = String(data: base64Data, encoding: .utf8) {
            return utf8Fallback
        }

        return trimmed
    }

    /// Decompresses raw deflate or zlib data using Apple's Compression framework
    private static func decompressDeflate(data: Data) -> Data? {
        let bufferSize = 1024 * 1024 * 4 // 4 MB destination buffer
        var destinationBuffer = [UInt8](repeating: 0, count: bufferSize)

        let decodedSize = data.withUnsafeBytes { rawBufferPointer -> Int in
            guard let baseAddress = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(
                &destinationBuffer,
                bufferSize,
                baseAddress,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if decodedSize > 0 {
            return Data(destinationBuffer.prefix(decodedSize))
        }

        // Try raw deflate algorithm if zlib headers not present
        let rawDecodedSize = data.withUnsafeBytes { rawBufferPointer -> Int in
            guard let baseAddress = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(
                &destinationBuffer,
                bufferSize,
                baseAddress,
                data.count,
                nil,
                COMPRESSION_LZFSE // or fallback
            )
        }

        if rawDecodedSize > 0 {
            return Data(destinationBuffer.prefix(rawDecodedSize))
        }

        return nil
    }

    /// Wraps decoded Aleatory script in the standard ALEATORY-001 HTML runtime harness
    public static func composeHTMLHarness(
        decompressedScript: String,
        seed: String,
        params: String? = nil
    ) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background-color: #000;
              display: flex;
              justify-content: center;
              align-items: center;
            }
            canvas {
              width: 100vw;
              height: 100vh;
              object-fit: contain;
            }
          </style>
          <script>
            // ALEATORY-001 Deterministic PRNG Harness (xmur3 + sfc32)
            function xmur3(str) {
              for (var i = 0, h = 1779033703 ^ str.length; i < str.length; i++) {
                h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
                h = h << 13 | h >>> 19;
              }
              return function() {
                h = Math.imul(h ^ (h >>> 16), 2246822507);
                h = Math.imul(h ^ (h >>> 13), 3266489909);
                return (h ^= h >>> 16) >>> 0;
              };
            }
            function sfc32(a, b, c, d) {
              return function() {
                a >>>= 0; b >>>= 0; c >>>= 0; d >>>= 0;
                var t = (a + b | 0) + d | 0;
                d = d + 1 | 0;
                a = b ^ b >>> 9;
                b = c + (c << 3) | 0;
                c = c << 21 | c >>> 11;
                c = c + t | 0;
                return (t >>> 0) / 4294967296;
              };
            }

            const _seedStr = "\(seed)";
            const _seedGen = xmur3(_seedStr);
            const _rand = sfc32(_seedGen(), _seedGen(), _seedGen(), _seedGen());

            window.$alea = {
              seed: _seedStr,
              params: \(params ?? "{}"),
              rnd: function(min, max) {
                const val = _rand();
                if (min === undefined) return val;
                if (max === undefined) return val * min;
                return min + val * (max - min);
              },
              ready: function() {
                window._aleaReady = true;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.desktopArt) {
                  window.webkit.messageHandlers.desktopArt.postMessage('ready');
                }
              }
            };
          </script>
        </head>
        <body>
          <script>
            \(decompressedScript)
          </script>
        </body>
        </html>
        """
    }
}
