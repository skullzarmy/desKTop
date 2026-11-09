import Foundation

/// Runtime engine for Bootloader (BTLDR) on-chain SVG generative art
public enum BootloaderRuntime {
    /// Composes a full BTLDR execution document injecting the canonical context
    public static func composeHTMLDocument(
        script: String,
        seed: String,
        iterationNumber: Int = 1,
        isPreview: Bool = true
    ) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100vw;
              height: 100vh;
              overflow: hidden;
              background-color: #000;
              display: flex;
              justify-content: center;
              align-items: center;
            }
            svg {
              width: 100vw;
              height: 100vh;
            }
          </style>
          <script>
            // BTLDR Canonical Execution Context
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

            window.BTLDR = {
              seed: _seedStr,
              iterationNumber: \(iterationNumber),
              isPreview: \(isPreview ? "true" : "false"),
              rnd: function(min, max) {
                const val = _rand();
                if (min === undefined) return val;
                if (max === undefined) return val * min;
                return min + val * (max - min);
              }
            };
          </script>
        </head>
        <body>
          <div id="btldr-root"></div>
          <script>
            \(script)
          </script>
        </body>
        </html>
        """
    }
}
