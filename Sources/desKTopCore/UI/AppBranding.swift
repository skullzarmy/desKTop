import AppKit
import Foundation

/// Generates razor-sharp, appearance-aware vector branding assets
public enum AppBranding {
    /// Returns dynamic appearance-aware NSImage for the macOS Menu Bar status item.
    /// In Dark Mode: Letters are pure white (#FFFFFF), play button is Tezos Blue (#2B72FF).
    /// In Light Mode: Letters are dark slate (#1E293B), play button is Tezos Blue (#2B72FF).
    @MainActor
    public static var dynamicMenuBarIcon: NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { rect in
            let scale = rect.width / 1024.0

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
            tPath.move(to: NSPoint(x: 290 * scale, y: 320 * scale))
            tPath.line(to: NSPoint(x: 734 * scale, y: 320 * scale))
            tPath.line(to: NSPoint(x: 734 * scale, y: 392 * scale))
            tPath.line(to: NSPoint(x: 636 * scale, y: 392 * scale))
            tPath.line(to: NSPoint(x: 636 * scale, y: 704 * scale))
            tPath.line(to: NSPoint(x: 564 * scale, y: 632 * scale))
            tPath.line(to: NSPoint(x: 564 * scale, y: 392 * scale))
            tPath.line(to: NSPoint(x: 290 * scale, y: 392 * scale))
            tPath.close()

            letterColor.setFill()
            tPath.fill()

            // 2. K-Letter Path: M 290 416 H 362 V 502 L 450 416 H 542 L 430 532 L 602 704 H 510 L 362 556 V 704 H 290 Z
            let kPath = NSBezierPath()
            kPath.move(to: NSPoint(x: 290 * scale, y: 416 * scale))
            kPath.line(to: NSPoint(x: 362 * scale, y: 416 * scale))
            kPath.line(to: NSPoint(x: 362 * scale, y: 502 * scale))
            kPath.line(to: NSPoint(x: 450 * scale, y: 416 * scale))
            kPath.line(to: NSPoint(x: 542 * scale, y: 416 * scale))
            kPath.line(to: NSPoint(x: 430 * scale, y: 532 * scale))
            kPath.line(to: NSPoint(x: 602 * scale, y: 704 * scale))
            kPath.line(to: NSPoint(x: 510 * scale, y: 704 * scale))
            kPath.line(to: NSPoint(x: 362 * scale, y: 556 * scale))
            kPath.line(to: NSPoint(x: 362 * scale, y: 704 * scale))
            kPath.line(to: NSPoint(x: 290 * scale, y: 704 * scale))
            kPath.close()

            letterColor.setFill()
            kPath.fill()

            // 3. Play Button Triangle: points="464,532 540,456 540,608"
            let playPath = NSBezierPath()
            playPath.move(to: NSPoint(x: 464 * scale, y: 532 * scale))
            playPath.line(to: NSPoint(x: 540 * scale, y: 456 * scale))
            playPath.line(to: NSPoint(x: 540 * scale, y: 608 * scale))
            playPath.close()

            playColor.setFill()
            playPath.fill()

            return true
        }
        return img
    }
}
