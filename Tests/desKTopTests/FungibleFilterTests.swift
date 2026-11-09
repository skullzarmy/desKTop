import Foundation
import desKTopCore

public struct FungibleFilterTests {
    public static func run() throws {
        let engine = FungibleFilterEngine()

        // 1. Art token accepted
        let artToken = UnifiedToken(
            contract: "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton",
            tokenId: "12345",
            name: "Generative Masterpiece",
            artifactUri: "ipfs://Qm123456789",
            displayUri: "ipfs://Qm123456789Display",
            supply: 10,
            decimals: 0
        )
        let res1 = engine.evaluate(artToken)
        try assertTrue(res1.isSuccess, "Art token should pass")

        // 2. Legacy HEN with nil decimals
        let henToken = UnifiedToken(
            contract: "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton",
            tokenId: "100",
            name: "HEN Genesis",
            artifactUri: "ipfs://Qm123456789",
            supply: 100,
            decimals: nil
        )
        let res2 = engine.evaluate(henToken)
        try assertTrue(res2.isSuccess, "Legacy HEN token with nil decimals should pass")

        // 3. Fungible token with decimals > 0 rejected
        let fungible = UnifiedToken(
            contract: "KT1GenericTokenContract1111111111111111",
            tokenId: "0",
            name: "Fungible Currency Token",
            artifactUri: "ipfs://Qm123",
            supply: 1000,
            decimals: 6
        )
        let res3 = engine.evaluate(fungible)
        if case .failure(let reason) = res3 {
            try assertEqual(reason, .nonZeroDecimals)
        } else {
            throw TestFailure("Fungible token should have failed filter")
        }

        // 4. Excessive supply rejected
        let spam = UnifiedToken(
            contract: "KT1Spam1234567890123456789012345678",
            tokenId: "1",
            name: "Spam Airdrop",
            artifactUri: "ipfs://QmSpam",
            supply: 50_000,
            decimals: 0
        )
        let res4 = engine.evaluate(spam)
        if case .failure(let reason) = res4 {
            try assertEqual(reason, .excessiveSupply)
        } else {
            throw TestFailure("Excessive supply token should have failed filter")
        }

        // 5. Missing visual media rejected
        let blank = UnifiedToken(
            contract: "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton",
            tokenId: "1",
            name: "No Visual Media",
            artifactUri: nil,
            displayUri: nil,
            supply: 1,
            decimals: 0
        )
        let res5 = engine.evaluate(blank)
        if case .failure(let reason) = res5 {
            try assertEqual(reason, .missingVisualMedia)
        } else {
            throw TestFailure("Blank visual media should have failed filter")
        }

        // 6. Blacklisted contract rejected
        let veNFT = UnifiedToken(
            contract: "KT18kkvmUoefkdok5mrjU6fxsm7xmumy1NEw",
            tokenId: "1",
            name: "veNFT Vote Marker",
            artifactUri: "ipfs://QmTest",
            supply: 1,
            decimals: 0
        )
        let res6 = engine.evaluate(veNFT)
        if case .failure(let reason) = res6 {
            try assertEqual(reason, .blacklistedContract)
        } else {
            throw TestFailure("Blacklisted contract should have failed filter")
        }

        // 7. Whitelist override
        let userWhitelisted: Set<String> = [veNFT.id]
        let res7 = engine.evaluate(veNFT, userWhitelistedIds: userWhitelisted)
        try assertTrue(res7.isSuccess, "User whitelist must override contract blacklist")

        // 8. User blacklist override
        let userBlacklisted: Set<String> = [artToken.id]
        let res8 = engine.evaluate(artToken, userBlacklistedIds: userBlacklisted)
        if case .failure(let reason) = res8 {
            try assertEqual(reason, .userBlacklisted)
        } else {
            throw TestFailure("User blacklisted token should have failed filter")
        }
    }
}
