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
        rawMetadata: [String: String]? = nil
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
        // Check for Aleatory contract or metadata
        if aleatory != nil || contract.lowercased() == "kt1aleatory" {
            return .aleatory
        }

        // Check for Bootloader (BTLDR) indicators
        if let desc = description, desc.contains("BTLDR") || desc.contains("bootloader") {
            return .bootloader
        }

        let mime = (mimeType ?? formats.first?.mimeType ?? "").lowercased()
        let uri = (artifactUri ?? "").lowercased()

        // Vector Graphics
        if mime == "image/svg+xml" || uri.hasSuffix(".svg") {
            return .vectorImage
        }

        // Animated Graphics
        if mime == "image/gif" || uri.hasSuffix(".gif") {
            return .animatedImage
        }

        // Videos
        if mime.hasPrefix("video/") || uri.hasSuffix(".mp4") || uri.hasSuffix(".webm") || uri.hasSuffix(".mov") {
            return .video
        }

        // Static Images
        if mime.hasPrefix("image/") {
            return .staticImage
        }

        // Interactive HTML / Generative
        if mime == "application/x-directory" || mime == "text/html" || uri.hasSuffix(".html") || uri.hasSuffix(".zip") {
            // Check for EditArt
            if uri.contains("editart") || (description?.contains("EditArt") ?? false) {
                return .editArt
            }
            // Check for fxhash
            if uri.contains("fxhash") || (rawMetadata?["symbol"]?.lowercased() == "fxhash") {
                return .fxhash
            }
            return .interactiveHtml
        }

        // 3D & Audio
        if mime.hasPrefix("model/") || mime.hasPrefix("audio/") || uri.hasSuffix(".gltf") || uri.hasSuffix(".glb") || uri.hasSuffix(".mp3") || uri.hasSuffix(".wav") {
            return .audio3d
        }

        return .unknown
    }
}
