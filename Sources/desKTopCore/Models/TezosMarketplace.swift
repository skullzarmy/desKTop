import Foundation

/// Detected Tezos marketplace / platform for a token or collection.
public enum TezosMarketplace: String, Equatable, Hashable, Sendable {
    case teia
    case aleatory
    case fxhash
    case bootloader
    case editArt
    case objkt

    public var displayName: String {
        switch self {
        case .teia: return "Teia"
        case .aleatory: return "Aleatory"
        case .fxhash: return "fxhash"
        case .bootloader: return "Bootloader"
        case .editArt: return "EditArt"
        case .objkt: return "objkt.com"
        }
    }

    public var shortName: String {
        switch self {
        case .teia: return "Teia"
        case .aleatory: return "Aleatory"
        case .fxhash: return "fxhash"
        case .bootloader: return "Bootloader"
        case .editArt: return "EditArt"
        case .objkt: return "objkt"
        }
    }

    public static let teiaContractAddresses: Set<String> = [
        "kt1rj6pbjhpwc3m5rw5s2nbmefwbuwbdxton", // hic et nunc / Teia FA2
        "kt1hkg5qenhfwpkw4fxvq7hgzb9z2enmcca9"  // HEN v1 minter
    ]

    public static func detect(contract: String, mediaCategory: MediaCategory? = nil, isFxhash: Bool = false, hasAleatoryMetadata: Bool = false, rawMetadata: [String: String]? = nil, uris: [String?] = []) -> TezosMarketplace {
        let lowerContract = contract.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if isFxhash || UnifiedToken.isFxhashContract(lowerContract) || mediaCategory == .fxhash {
            return .fxhash
        }

        if hasAleatoryMetadata || mediaCategory == .aleatory {
            return .aleatory
        }

        if mediaCategory == .bootloader {
            return .bootloader
        }

        if mediaCategory == .editArt {
            return .editArt
        }

        let contractAlias = (rawMetadata?["contractAlias"] ?? "").lowercased()
        let tags = (rawMetadata?["tags"] ?? "").lowercased()
        let platform = (rawMetadata?["platform"] ?? "").lowercased()
        let minter = (rawMetadata?["minter"] ?? "").lowercased()
        let joinedUris = uris.compactMap { $0?.lowercased() }.joined(separator: " ")

        if contractAlias.contains("aleatory") || tags.contains("aleatory") || platform.contains("aleatory") || joinedUris.contains("aleatory.art") {
            return .aleatory
        }

        if teiaContractAddresses.contains(lowerContract) ||
           contractAlias.contains("teia") ||
           contractAlias.contains("hic et nunc") ||
           tags.contains("teia") ||
           platform.contains("teia") ||
           minter.contains("teia") ||
           joinedUris.contains("teia.art") {
            return .teia
        }

        return .objkt
    }
}

public extension UnifiedToken {
    /// Detected Tezos marketplace / platform for this token.
    var marketplace: TezosMarketplace {
        TezosMarketplace.detect(
            contract: contract,
            mediaCategory: mediaCategory,
            isFxhash: isFxhash,
            hasAleatoryMetadata: aleatory != nil,
            rawMetadata: rawMetadata,
            uris: [artifactUri, displayUri, thumbnailUri]
        )
    }

    /// Primary marketplace token URL (Teia, Aleatory, fxhash, EditArt, or objkt.com).
    var marketplaceTokenURL: URL? {
        switch marketplace {
        case .teia:
            if TezosMarketplace.teiaContractAddresses.contains(contract.lowercased()) {
                return URL(string: "https://teia.art/objkt/\(tokenId)")
            }
            return objktTokenURL
        case .aleatory:
            return URL(string: "https://aleatory.art")
        case .fxhash:
            return fxhashGentkURL ?? objktTokenURL
        case .editArt:
            return URL(string: "https://www.editart.xyz")
        case .bootloader, .objkt:
            return objktTokenURL
        }
    }

    /// Primary marketplace collection URL.
    func marketplaceCollectionURL(projectId: String? = nil) -> URL? {
        switch marketplace {
        case .teia:
            return URL(string: "https://teia.art")
        case .aleatory:
            return URL(string: "https://aleatory.art")
        case .fxhash:
            return fxhashProjectURL(projectId: projectId) ?? objktCollectionURL(projectId: projectId)
        case .editArt:
            return URL(string: "https://www.editart.xyz")
        case .bootloader, .objkt:
            return objktCollectionURL(projectId: projectId)
        }
    }
}
