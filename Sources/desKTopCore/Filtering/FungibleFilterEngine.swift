import Foundation

/// Reason a token failed the art NFT filter
public enum FilterRejectionReason: String, Error, Sendable {
    case nonZeroDecimals = "Token has decimals > 0 (fungible token)"
    case excessiveSupply = "Total supply exceeds 10,000 edition threshold"
    case missingVisualMedia = "Token does not have an artifactUri or displayUri"
    case blacklistedContract = "Token contract is a known DeFi, governance, or LP contract"
    case userBlacklisted = "Token or collection has been manually hidden by user"
}

/// Strict multi-stage composite art NFT filter ensuring fungible and DeFi tokens never appear as wallpapers
public final class FungibleFilterEngine: Sendable {
    /// Known governance, voting escrow (veNFT), liquidity pool (DEX), and non-art registrar contracts
    public static let defaultBlacklistedContracts: Set<String> = [
        "KT18kkvmUoefkdok5mrjU6fxsm7xmumy1NEw", // veNFT
        "KT1K9gCRgaLRFKTErYt1wVxA3Frb9FjasjTV", // Kolibri governance
        "KT1JBmbKbqTyKaD6ULGZGSBKirZOGZH8DkAS", // Quipu governance
        "KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS"  // Tezos Domains Registrar
    ]

    /// Default maximum edition supply threshold for art tokens
    public static let defaultMaxSupplyThreshold: Int = 10_000

    private let blacklistedContracts: Set<String>
    private let maxSupplyThreshold: Int

    public init(
        additionalBlacklist: Set<String> = [],
        maxSupplyThreshold: Int = defaultMaxSupplyThreshold
    ) {
        self.blacklistedContracts = Self.defaultBlacklistedContracts.union(additionalBlacklist)
        self.maxSupplyThreshold = maxSupplyThreshold
    }

    /// Evaluates whether a token qualifies as an art NFT suitable for desktop wallpaper
    public func evaluate(
        _ token: UnifiedToken,
        userWhitelistedIds: Set<String> = [],
        userBlacklistedIds: Set<String> = []
    ) -> Result<Void, FilterRejectionReason> {
        // 1. Explicit user whitelist always passes
        if userWhitelistedIds.contains(token.id) || userWhitelistedIds.contains(token.contract) {
            return .success(())
        }

        // 2. Explicit user blacklist always fails
        if userBlacklistedIds.contains(token.id) || userBlacklistedIds.contains(token.contract) {
            return .failure(.userBlacklisted)
        }

        // 3. Known DeFi / Governance contract blacklist
        if blacklistedContracts.contains(token.contract) {
            return .failure(.blacklistedContract)
        }

        // 4. Decimals filter: decimals must be 0 or nil (legacy HEN tokens often have nil decimals)
        if let decimals = token.decimals, decimals > 0 {
            return .failure(.nonZeroDecimals)
        }

        // 5. Supply threshold: exclude collections/tokens with supply > maxSupplyThreshold
        if let supply = token.supply, supply > maxSupplyThreshold {
            return .failure(.excessiveSupply)
        }

        // 6. Visual Media check: Must possess artifactUri or displayUri
        let hasArtifact = token.artifactUri?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasDisplay = token.displayUri?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasArtifact || hasDisplay else {
            return .failure(.missingVisualMedia)
        }

        return .success(())
    }

    /// Filters an array of tokens, returning only genuine art NFTs
    public func filter(
        _ tokens: [UnifiedToken],
        userWhitelistedIds: Set<String> = [],
        userBlacklistedIds: Set<String> = []
    ) -> [UnifiedToken] {
        return tokens.filter { token in
            evaluate(token, userWhitelistedIds: userWhitelistedIds, userBlacklistedIds: userBlacklistedIds).isSuccess
        }
    }
}

extension Result {
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
