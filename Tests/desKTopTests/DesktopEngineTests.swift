import AppKit
import Foundation
import desKTopCore

public struct DesktopEngineTests {
    public static func run() async throws {
        // 1. DisplayManager persistent UUID
        let uuid = DisplayManager.persistentUUID(for: 1)
        try assertTrue(!uuid.isEmpty, "UUID should not be empty")

        // 2. Active displays enumeration
        let displays = await DisplayManager.activeDisplays()
        try assertTrue(!displays.isEmpty, "Should detect at least one active screen")
        let first = displays.first!
        try assertTrue(first.width > 0 && first.height > 0, "Display dimensions should be positive")

        // 3. StillWallpaperService cache busting
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dummySource = tempDir.appendingPathComponent("source.png")
        try Data([1, 2, 3]).write(to: dummySource)

        let service = StillWallpaperService(activeDirectory: tempDir)
        let unique1 = try service.prepareCacheBustedURL(sourceURL: dummySource, tokenId: "100")
        try assertTrue(unique1.lastPathComponent.contains("wallpaper_100_"))
        try assertTrue(FileManager.default.fileExists(atPath: unique1.path))

        // 4. DesktopCanvasWindowController
        await MainActor.run {
            if let screen = NSScreen.main {
                let controller = DesktopCanvasWindowController(screen: screen, displayUUID: first.uuid)
                let panel = controller.window as? NSPanel
                assert(panel != nil)
                assert(panel?.hasShadow == false)
                assert(panel?.sharingType == NSWindow.SharingType.none)
                assert(panel?.ignoresMouseEvents == true)
            }
        }
    }
}
