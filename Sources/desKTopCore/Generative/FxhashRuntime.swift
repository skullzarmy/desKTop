import Foundation

/// Runtime harness injector for fxhash and drop.art HTML tokens
public enum FxhashRuntime {
    /// Injects standard $fxhash and fxpreview hook into HTML content
    public static func injectHarness(into htmlContent: String, seed: String, iteration: Int = 1) -> String {
        let injectionScript = """
        <script>
          // Injected fxhash runtime harness
          let alphabet = "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";
          var fxhash = "\(seed)";
          let b58dec = str=>[...str].reduce((p,c)=>p*alphabet.length+alphabet.indexOf(c)|0, 0);
          let fxhashTrunc = fxhash.slice(2);
          let regex = new RegExp(".{" + ((fxhashTrunc.length/4)|0) + "}", 'g');
          let hashes = fxhashTrunc.match(regex).map(h => b58dec(h));
          let sfc32 = (a, b, c, d) => {
            return () => {
              a >>>= 0; b >>>= 0; c >>>= 0; d >>>= 0;
              var t = (a + b | 0) + d | 0;
              d = d + 1 | 0;
              a = b ^ b >>> 9;
              b = c + (c << 3) | 0;
              c = c << 21 | c >>> 11;
              c = c + t | 0;
              return (t >>> 0) / 4294967296;
            };
          };
          var fxrand = sfc32(...hashes);
          var isFxpreview = false;
          function fxpreview() {
            window._fxpreviewTriggered = true;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.desktopArt) {
              window.webkit.messageHandlers.desktopArt.postMessage('fxpreview');
            }
          }
          window.$fx = {
            hash: fxhash,
            rand: fxrand,
            preview: fxpreview,
            iteration: \(iteration),
            features: function(feats) {
              window.$fxhashFeatures = feats;
            }
          };
        </script>
        """

        if let headRange = htmlContent.range(of: "<head>", options: .caseInsensitive) {
            var modified = htmlContent
            modified.insert(contentsOf: injectionScript, at: headRange.upperBound)
            return modified
        } else {
            return injectionScript + htmlContent
        }
    }
}
