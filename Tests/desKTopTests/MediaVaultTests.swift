import Foundation
import desKTopCore

public struct MediaVaultTests {
    public static func run() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let vault = MediaVault(cacheDirectory: tempDir)

        // 1. Cache key determinism
        let uri = "ipfs://QmTest123"
        let key1 = MediaVault.cacheKey(for: uri)
        let key2 = MediaVault.cacheKey(for: uri)
        try assertEqual(key1, key2)
        try assertTrue(!key1.isEmpty)

        // 2. Initial state: not cached
        let initial = await vault.localCachedURL(for: uri)
        try assertNil(initial)

        // 3. Manual file caching & retrieval
        let sampleData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG
        let filePath = tempDir.appendingPathComponent("\(key1).png")
        try sampleData.write(to: filePath)

        let cached = await vault.localCachedURL(for: uri)
        try assertNotNil(cached)
        try assertEqual(cached?.resolvingSymlinksInPath().path, filePath.resolvingSymlinksInPath().path)

        // 4. Cache size
        let size = await vault.totalCacheSize()
        try assertTrue(size > 0, "Cache size should reflect written file")

        // 5. Clear cache
        try await vault.clearCache()
        let clearedSize = await vault.totalCacheSize()
        try assertEqual(clearedSize, 0)
    }
}
