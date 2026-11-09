import AppKit
import Foundation

/// Generates razor-sharp, appearance-aware vector branding assets
public enum AppBranding {
    /// Returns dynamic appearance-aware NSImage for the macOS Menu Bar status item.
    /// In Dark Mode: Letters are pure white (#FFFFFF), play button is Tezos Blue (#2B72FF).
    /// In Light Mode: Letters are dark slate (#1E293B), play button is Tezos Blue (#2B72FF).
    @MainActor
    public static var dynamicMenuBarIcon: NSImage {
        let size = NSSize(width: 20, height: 18)
        let img = NSImage(size: size, flipped: true) { rect in
            let scale: CGFloat = min((rect.width - 2.0) / 444.0, (rect.height - 2.0) / 384.0)
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(
                    x: (x - 512.0) * scale + rect.midX,
                    y: (y - 512.0) * scale + rect.midY
                )
            }

            let isDark: Bool = {
                if let bestMatch = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) {
                    return bestMatch == .darkAqua
                }
                return true // default to dark aesthetic
            }()

            let letterColor = isDark ? NSColor.white : NSColor(srgbRed: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
            let playColor = NSColor(srgbRed: 0x2B / 255.0, green: 0x72 / 255.0, blue: 1.0, alpha: 1.0)

            // 1. T-Letter Path: M 290 320 H 734 V 392 H 636 V 704 L 564 632 V 392 H 290 Z
            let tPath = NSBezierPath()
            tPath.move(to: pt(290, 320))
            tPath.line(to: pt(734, 320))
            tPath.line(to: pt(734, 392))
            tPath.line(to: pt(636, 392))
            tPath.line(to: pt(636, 704))
            tPath.line(to: pt(564, 632))
            tPath.line(to: pt(564, 392))
            tPath.line(to: pt(290, 392))
            tPath.close()

            letterColor.setFill()
            tPath.fill()

            // 2. K-Letter Path: M 290 416 H 362 V 502 L 450 416 H 542 L 430 532 L 602 704 H 510 L 362 556 V 704 H 290 Z
            let kPath = NSBezierPath()
            kPath.move(to: pt(290, 416))
            kPath.line(to: pt(362, 416))
            kPath.line(to: pt(362, 502))
            kPath.line(to: pt(450, 416))
            kPath.line(to: pt(542, 416))
            kPath.line(to: pt(430, 532))
            kPath.line(to: pt(602, 704))
            kPath.line(to: pt(510, 704))
            kPath.line(to: pt(362, 556))
            kPath.line(to: pt(362, 704))
            kPath.line(to: pt(290, 704))
            kPath.close()

            letterColor.setFill()
            kPath.fill()

            // 3. Play Button Triangle: points="464,532 540,456 540,608"
            let playPath = NSBezierPath()
            playPath.move(to: pt(464, 532))
            playPath.line(to: pt(540, 456))
            playPath.line(to: pt(540, 608))
            playPath.close()

            playColor.setFill()
            playPath.fill()

            return true
        }
        img.isTemplate = false
        return img
    }
}
