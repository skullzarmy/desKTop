import Foundation

/// Standard format entry within token metadata (dimensions, mimeType, hash)
public struct TokenFormat: Hashable, Codable, Sendable {
    public let uri: String?
    public let mimeType: String?
    public let dimensions: String?
    public let fileSize: Int64?
    public let hash: String?

    public init(
        uri: String? = nil,
        mimeType: String? = nil,
        dimensions: String? = nil,
        fileSize: Int64? = nil,
        hash: String? = nil
    ) {
        self.uri = uri
        self.mimeType = mimeType
        self.dimensions = dimensions
        self.fileSize = fileSize
        self.hash = hash
    }
}

/// Token attribute (trait, feature, generative seed property)
public struct TokenAttribute: Hashable, Codable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Aleatory specific metadata and runtime payload
public struct AleatoryMetadata: Hashable, Codable, Sendable {
    public let code: String?
    public let seed: String?
    public let params: String?
    public let provider: String?
    public let encoding: String?
    public let version: Int?

    public init(
        code: String? = nil,
        seed: String? = nil,
        params: String? = nil,
        provider: String? = nil,
        encoding: String? = nil,
        version: Int? = nil
    ) {
        self.code = code
        self.seed = seed
        self.params = params
        self.provider = provider
        self.encoding = encoding
        self.version = version
    }
}

/// Media category classification for wallpaper rendering
public enum MediaCategory: String, Hashable, Codable, Sendable {
    case staticImage
    case vectorImage
    case animatedImage
    case video
    case interactiveHtml
    case aleatory
    case bootloader
    case editArt
    case fxhash
    case audio3d
    case unknown
}

/// Normalized canonical token model across all Tezos indexers (TzKT, objkt.com, Aleatory)
public struct UnifiedToken: Identifiable, Hashable, Codable, Sendable {
    /// Composite key: contractAddress_tokenId
    public var id: String {
        "\(contract)_\(tokenId)"
    }

    public let contract: String
    public let tokenId: String
    public let name: String
    public let description: String?
    public let creators: [String]
    public let mimeType: String?
    public let artifactUri: String?
    public let displayUri: String?
    public let thumbnailUri: String?
    public let formats: [TokenFormat]
    public let attributes: [TokenAttribute]
    public let supply: Int?
    public let decimals: Int?
    public let aleatory: AleatoryMetadata?
    public let rawMetadata: [String: String]?
    public var isOwned: Bool
    public var isCreated: Bool

    public init(
        contract: String,
        tokenId: String,
        name: String,
        description: String? = nil,
        creators: [String] = [],
        mimeType: String? = nil,
        artifactUri: String? = nil,
        displayUri: String? = nil,
        thumbnailUri: String? = nil,
        formats: [TokenFormat] = [],
        attributes: [TokenAttribute] = [],
        supply: Int? = nil,
        decimals: Int? = nil,
        aleatory: AleatoryMetadata? = nil,
        rawMetadata: [String: String]? = nil,
        isOwned: Bool = true,
        isCreated: Bool = false
    ) {
        self.contract = contract
        self.tokenId = tokenId
        self.name = name
        self.description = description
        self.creators = creators
        self.mimeType = mimeType
        self.artifactUri = artifactUri
        self.displayUri = displayUri
        self.thumbnailUri = thumbnailUri
        self.formats = formats
        self.attributes = attributes
        self.supply = supply
        self.decimals = decimals
        self.aleatory = aleatory
        self.rawMetadata = rawMetadata
        self.isOwned = isOwned
        self.isCreated = isCreated
    }

    /// Primary URI to render as wallpaper (displayUri preferred for audio/3D, artifactUri preferred for visuals)
    public var primaryWallpaperUri: String? {
        if mediaCategory == .audio3d {
            return displayUri ?? thumbnailUri ?? artifactUri
        }
        return artifactUri ?? displayUri ?? thumbnailUri
    }

    /// Determines the media rendering category based on MIME type, contract, and metadata
    public var mediaCategory: MediaCategory {
        let lowerContract = contract.lowercased()
        let uri = (artifactUri ?? "").lowercased()
        let display = (displayUri ?? "").lowercased()
        let mime = (mimeType ?? formats.first?.mimeType ?? "").lowercased()
        let desc = description ?? ""

        // 1. Aleatory on-chain generative art
        if aleatory != nil ||
           lowerContract == "kt1aleatory" ||
           rawMetadata?["aleatory"] != nil ||
           rawMetadata?["generator"]?.lowercased().contains("aleatory") == true ||
           name.lowercased().contains("aleatory") {
            return .aleatory
        }

        // 2. Bootloader (BTLDR) bytecode generative art
        if desc.contains("BTLDR") || desc.contains("bootloader") || name.contains("BTLDR") || name.contains("Bootloader") {
            return .bootloader
        }

        // 3. fxhash Generative Tokens
        // Known fxhash contracts:
        // KT1KEa8z6vWXDJrVqtMrAeDVzsvxat3kHaCE (fxhash v1 gentk)
        // KT1U6EHmng3rqGzgWRjVm31tYmGwgyMo61gk (fxhash v2 gentk)
        // KT1EfsNuqwLACdq3mAA3gkpjTrMmqqeS2nuv (fxhash v3 gentk)
        let fxhashContracts: Set<String> = [
            "kt1kea8z6vwxdjrvqtmraedvzsvxat3khace",
            "kt1u6ehmng3rqgzgwrjvm31tymgwgymo61gk",
            "kt1efsnuqwlacdq3maa3gkpjtrmmqqes2nuv"
        ]

        if fxhashContracts.contains(lowerContract) ||
           uri.contains("fxhash=") ||
           rawMetadata?["symbol"]?.uppercased() == "GENTK" ||
           rawMetadata?["iterationHash"] != nil ||
           rawMetadata?["generatorUri"] != nil ||
           rawMetadata?["authenticityHash"] != nil {
            return .fxhash
        }

        // 4. EditArt
        if uri.contains("editart") || desc.contains("EditArt") || name.contains("EditArt") {
            return .editArt
        }

        // 5. Interactive HTML / Web Generative art
        if mime == "application/x-directory" || mime == "text/html" ||
           uri.hasSuffix(".html") || uri.hasSuffix(".zip") ||
           uri.contains(".html?") || uri.contains(".zip?") {
            return .interactiveHtml
        }

        // 6. Vector Graphics
        if mime == "image/svg+xml" || uri.hasSuffix(".svg") || display.hasSuffix(".svg") {
            return .vectorImage
        }

        // 7. Animated Graphics
        if mime == "image/gif" || uri.hasSuffix(".gif") || display.hasSuffix(".gif") {
            return .animatedImage
        }

        // 8. Videos
        if mime.hasPrefix("video/") || uri.hasSuffix(".mp4") || uri.hasSuffix(".webm") || uri.hasSuffix(".mov") ||
           display.hasSuffix(".mp4") || display.hasSuffix(".webm") || display.hasSuffix(".mov") {
            return .video
        }

        // 9. 3D & Audio (checked before display poster image fallback)
        if mime.hasPrefix("model/") || mime.hasPrefix("audio/") ||
           uri.hasSuffix(".gltf") || uri.hasSuffix(".glb") ||
           uri.hasSuffix(".mp3") || uri.hasSuffix(".wav") {
            return .audio3d
        }

        // 10. Static Images
        if mime.hasPrefix("image/") || uri.hasSuffix(".png") || uri.hasSuffix(".jpg") || uri.hasSuffix(".jpeg") || uri.hasSuffix(".webp") ||
           display.hasSuffix(".png") || display.hasSuffix(".jpg") || display.hasSuffix(".jpeg") || display.hasSuffix(".webp") {
            return .staticImage
        }

        // 11. Fallback for tokens with display or thumbnail
        if displayUri != nil || thumbnailUri != nil {
            return .staticImage
        }

        return .unknown
    }
}
