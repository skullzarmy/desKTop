import Foundation
import desKTopCore

public struct WalletRepositoryTests {
    public static func run() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let repository = WalletRepository(storageDirectory: tempDirectory)

        // 1. Source management
        let addr = TezosAddress("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")!
        let domain = TezosDomain("alice.tez")!
        let source = WalletSource.fromAddress(addr, domain: domain)

        let initial = await repository.getSources()
        try assertEqual(initial.count, 0)

        try await repository.addSource(source)
        let sources = await repository.getSources()
        try assertEqual(sources.count, 1)
        try assertEqual(sources.first?.displayName, "alice.tez")

        // Update
        var updated = sources.first!
        updated.displayName = "My Primary Vault"
        try await repository.updateSource(updated)

        let reloaded = await repository.getSources()
        try assertEqual(reloaded.first?.displayName, "My Primary Vault")

        // Remove
        try await repository.removeSource(id: updated.id)
        let empty = await repository.getSources()
        try assertEqual(empty.count, 0)

        // 2. Whitelist & Blacklist
        let tokenId = "KT1test_1"
        try await repository.whitelistToken(id: tokenId)
        var whitelist = await repository.getWhitelist()
        try assertTrue(whitelist.contains(tokenId))

        try await repository.blacklistToken(id: tokenId)
        whitelist = await repository.getWhitelist()
        let blacklist = await repository.getBlacklist()
        try assertFalse(whitelist.contains(tokenId))
        try assertTrue(blacklist.contains(tokenId))

        // 3. Token upsert
        let token1 = UnifiedToken(contract: "KT1a", tokenId: "1", name: "Art A")
        let token2 = UnifiedToken(contract: "KT1a", tokenId: "2", name: "Art B")

        try await repository.upsertTokens([token1, token2])
        var tokens = await repository.getTokens()
        try assertEqual(tokens.count, 2)

        let token1Updated = UnifiedToken(contract: "KT1a", tokenId: "1", name: "Art A (Remastered)")
        try await repository.upsertTokens([token1Updated])

        tokens = await repository.getTokens()
        try assertEqual(tokens.count, 2)
        let found = tokens.first(where: { $0.id == token1.id })
        try assertEqual(found?.name, "Art A (Remastered)")
    }
}
