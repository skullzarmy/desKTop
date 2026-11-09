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

        // 4. Smart Galleries (Dynamic Filter Rules) vs Curated Galleries (Hand-Picked Items)
        let gifToken = UnifiedToken(
            contract: "KT1gif",
            tokenId: "10",
            name: "Animated Motion Piece",
            mimeType: "image/gif"
        )
        let stillToken = UnifiedToken(
            contract: "KT1still",
            tokenId: "20",
            name: "Static Oil Painting",
            mimeType: "image/jpeg"
        )
        try await repository.upsertTokens([gifToken, stillToken])

        // Create Smart Gallery matching format "GIF"
        let smartCriteria = GalleryFilterCriteria(formatFilter: "GIF")
        let smartGallery = try await repository.createSmartGallery(
            name: "Only GIFs",
            description: "Smart dynamic playlist",
            criteria: smartCriteria
        )
        try assertTrue(smartGallery.isSmart)
        try assertEqual(smartGallery.type, .smart)

        // Matching tokens dynamically evaluates against library
        let currentTokens = await repository.getTokens()
        let smartMatches = smartGallery.matchingTokens(from: currentTokens)
        try assertEqual(smartMatches.count, 1)
        try assertEqual(smartMatches.first?.name, "Animated Motion Piece")

        // Create Hand-Curated Gallery with stillToken
        let manualGallery = try await repository.createManualGallery(
            name: "Favorites",
            description: "Hand-picked items",
            tokenIds: [stillToken.id]
        )
        try assertFalse(manualGallery.isSmart)
        try assertEqual(manualGallery.type, .manual)
        let manualMatches = manualGallery.matchingTokens(from: currentTokens)
        try assertEqual(manualMatches.count, 1)
        try assertEqual(manualMatches.first?.name, "Static Oil Painting")

        // 5. Following a Wallet / Creator as a Smart Gallery
        let artistAddr = "tz1ArtistWallet1234567890123456789012"
        let artistToken = UnifiedToken(
            contract: "KT1art",
            tokenId: "1",
            name: "Artist Masterpiece",
            creators: [artistAddr],
            mimeType: "image/png"
        )
        try await repository.upsertTokens([artistToken])

        let artistFollowCriteria = GalleryFilterCriteria(targetWallet: artistAddr, walletScope: .created)
        let artistGallery = try await repository.createSmartGallery(
            name: "Created by Artist",
            criteria: artistFollowCriteria
        )
        try assertTrue(artistGallery.isSmart)
        let allTokens = await repository.getTokens()
        let artistMatches = artistGallery.matchingTokens(from: allTokens)
        try assertEqual(artistMatches.count, 1)
        try assertEqual(artistMatches.first?.name, "Artist Masterpiece")
    }
}
