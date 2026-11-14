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

    public var displayName: String {
        switch self {
        case .staticImage: return "Image"
        case .vectorImage: return "Vector"
        case .animatedImage: return "GIF"
        case .video: return "Video"
        case .interactiveHtml: return "Interactive"
        case .aleatory: return "Aleatory"
        case .bootloader: return "Bytecode"
        case .editArt: return "EditArt"
        case .fxhash: return "Generative"
        case .audio3d: return "3D / Audio"
        case .unknown: return "Artwork"
        }
    }
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
    public var accessibilityHazards: [String]
    public var contentRating: String?
    public var moderationFlag: String?
    public var isOwned: Bool
    public var isCreated: Bool

    enum CodingKeys: String, CodingKey {
        case contract, tokenId, name, description, creators, mimeType
        case artifactUri, displayUri, thumbnailUri, formats, attributes
        case supply, decimals, aleatory, rawMetadata
        case accessibilityHazards, contentRating, moderationFlag
        case isOwned, isCreated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contract = try container.decode(String.self, forKey: .contract)
        self.tokenId = try container.decode(String.self, forKey: .tokenId)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.creators = try container.decodeIfPresent([String].self, forKey: .creators) ?? []
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.artifactUri = try container.decodeIfPresent(String.self, forKey: .artifactUri)
        self.displayUri = try container.decodeIfPresent(String.self, forKey: .displayUri)
        self.thumbnailUri = try container.decodeIfPresent(String.self, forKey: .thumbnailUri)
        self.formats = try container.decodeIfPresent([TokenFormat].self, forKey: .formats) ?? []
        self.attributes = try container.decodeIfPresent([TokenAttribute].self, forKey: .attributes) ?? []
        self.supply = try container.decodeIfPresent(Int.self, forKey: .supply)
        self.decimals = try container.decodeIfPresent(Int.self, forKey: .decimals)
        self.aleatory = try container.decodeIfPresent(AleatoryMetadata.self, forKey: .aleatory)
        self.rawMetadata = try container.decodeIfPresent([String: String].self, forKey: .rawMetadata)
        self.accessibilityHazards = try container.decodeIfPresent([String].self, forKey: .accessibilityHazards) ?? []
        self.contentRating = try container.decodeIfPresent(String.self, forKey: .contentRating)
        self.moderationFlag = try container.decodeIfPresent(String.self, forKey: .moderationFlag)
        self.isOwned = try container.decodeIfPresent(Bool.self, forKey: .isOwned) ?? true
        self.isCreated = try container.decodeIfPresent(Bool.self, forKey: .isCreated) ?? false
    }

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
        accessibilityHazards: [String] = [],
        contentRating: String? = nil,
        moderationFlag: String? = nil,
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
        self.accessibilityHazards = accessibilityHazards
        self.contentRating = contentRating
        self.moderationFlag = moderationFlag
        self.isOwned = isOwned
        self.isCreated = isCreated
    }

    public var hasFlashingHazard: Bool {
        if accessibilityHazards.contains(where: { $0.localizedCaseInsensitiveContains("flash") }) {
            return true
        }
        return attributes.contains { attr in
            attr.name == "__hazards_" && attr.value.localizedCaseInsensitiveContains("flash")
        }
    }

    public var isAdultContent: Bool {
        if let rating = contentRating?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           rating == "mature" || rating == "nsfw" || rating == "adult" {
            return true
        }
        return attributes.contains { attr in
            attr.name == "__nsfw_" && ["true", "1", "yes"].contains(attr.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    public var isModerationFlagged: Bool {
        guard let flag = moderationFlag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !flag.isEmpty else {
            return false
        }
        return flag != "none"
    }

    public func isHiddenByContentFilters(hideFlashing: Bool, hideAdult: Bool, hideFlagged: Bool) -> Bool {
        if hideFlashing && hasFlashingHazard { return true }
        if hideAdult && isAdultContent { return true }
        if hideFlagged && isModerationFlagged { return true }
        return false
    }

    private static let isoFormatterLock = NSLock()
    nonisolated(unsafe) private static let standardISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Date token was acquired or minted
    public var acquiredDate: Date? {
        guard let raw = rawMetadata?["lastTime"] ?? rawMetadata?["firstTime"] ?? rawMetadata?["timestamp"] else {
            return nil
        }
        Self.isoFormatterLock.lock()
        defer { Self.isoFormatterLock.unlock() }
        if let d = Self.standardISOFormatter.date(from: raw) {
            return d
        }
        return Self.fractionalISOFormatter.date(from: raw)
    }

    /// Tests whether a URI string points to visual/displayable media rather than raw metadata text or JSON
    public static func isVisualUri(_ uriString: String?) -> Bool {
        guard let u = uriString?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return false }
        let lower = u.lowercased()
        if lower.hasSuffix(".json") || lower.contains("/metadata") || lower.hasSuffix(".md") || lower.hasSuffix(".txt") || lower.hasSuffix(".pdf") {
            return false
        }
        return true
    }

    /// Best visual thumbnail URI (filters out generic HEN placeholder icons, non-visual metadata, and non-image artifacts like video/HTML)
    public var preferredThumbnailUri: String? {
        let henPlaceholder = "QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc"
        let category = mediaCategory

        let nonImageArtifactCategories: Set<MediaCategory> = [
            .video, .audio3d, .interactiveHtml, .fxhash, .editArt, .aleatory, .bootloader
        ]

        if let thumb = thumbnailUri, Self.isVisualUri(thumb), !thumb.contains(henPlaceholder) {
            return thumb
        }
        if let disp = displayUri, Self.isVisualUri(disp), !disp.contains(henPlaceholder) {
            return disp
        }
        if !nonImageArtifactCategories.contains(category),
           let art = artifactUri, Self.isVisualUri(art) {
            return art
        }
        if let thumb = thumbnailUri, Self.isVisualUri(thumb) { return thumb }
        if let disp = displayUri, Self.isVisualUri(disp) { return disp }
        return nonImageArtifactCategories.contains(category) ? nil : artifactUri
    }

    /// Primary URI to render as wallpaper (displayUri preferred for audio/3D, artifactUri preferred for visuals; rejects raw JSON/text)
    public var primaryWallpaperUri: String? {
        if mediaCategory == .audio3d {
            if let disp = displayUri, Self.isVisualUri(disp) { return disp }
            if let thumb = thumbnailUri, Self.isVisualUri(thumb) { return thumb }
            if let art = artifactUri, Self.isVisualUri(art) { return art }
        }

        // Interactive / generative art relies on artifactUri
        if isFxhash || mediaCategory == .interactiveHtml || mediaCategory == .aleatory || mediaCategory == .bootloader {
            if let art = artifactUri, Self.isVisualUri(art) || art.contains("fxhash=") {
                return art
            }
        }

        // Visual tokens: artifactUri if visual, else fallback to displayUri or thumbnailUri
        if let art = artifactUri, Self.isVisualUri(art) {
            return art
        }
        if let disp = displayUri, Self.isVisualUri(disp) {
            return disp
        }
        if let thumb = thumbnailUri, Self.isVisualUri(thumb) {
            return thumb
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

        // 7. Animated Graphics (GIFs)
        let isGifMime = mime == "image/gif"
        let isGifUri = uri.hasSuffix(".gif") || display.hasSuffix(".gif")
        let isGifInFormats = formats.contains { f in
            let fm = (f.mimeType ?? "").lowercased()
            let fu = (f.uri ?? "").lowercased()
            return fm == "image/gif" || fu.hasSuffix(".gif")
        }
        let hasGifTag = (rawMetadata?["tags"] ?? "").lowercased().contains("gif")
        let isGifRaw = (rawMetadata?["mime"] ?? rawMetadata?["mimeType"] ?? "").lowercased() == "image/gif"
        if isGifMime || isGifUri || isGifInFormats || hasGifTag || isGifRaw {
            return .animatedImage
        }

        // 8. Videos
        let isVideoMime = mime.hasPrefix("video/")
        let isVideoUri = uri.hasSuffix(".mp4") || uri.hasSuffix(".webm") || uri.hasSuffix(".mov") ||
            display.hasSuffix(".mp4") || display.hasSuffix(".webm") || display.hasSuffix(".mov")
        let isVideoInFormats = formats.contains { f in
            let fm = (f.mimeType ?? "").lowercased()
            let fu = (f.uri ?? "").lowercased()
            return fm.hasPrefix("video/") || fu.hasSuffix(".mp4") || fu.hasSuffix(".webm") || fu.hasSuffix(".mov")
        }
        if isVideoMime || isVideoUri || isVideoInFormats {
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

    // MARK: - fxhash Project Helpers

    /// Whether this token is an fxhash generative token across all 3 generations
    public var isFxhash: Bool {
        return mediaCategory == .fxhash ||
               rawMetadata?["symbol"]?.uppercased() == "GENTK" ||
               (artifactUri ?? "").contains("fxhash=") ||
               Self.isFxhashContract(contract)
    }

    public static func isFxhashContract(_ address: String) -> Bool {
        let lower = address.lowercased()
        return lower == "kt1kea8z6vwxdjrvqtmraedvzsvxat3khace" ||
               lower == "kt1u6ehmnxjtkvawj4thczg4fsdahc21ssvi" ||
               lower == "kt1u6ehmng3rqgzgwrjvm31tymgwgymo61gk" ||
               lower == "kt1efsnuqwlawdd3o4pvfux1cah5gmdtrrvr" ||
               lower == "kt1efsnuqwlacdq3maa3gkpjtrmmqqes2nuv"
    }

    /// The fxhash generation variant (v1 Vanilla, v2, v3 fx(params))
    public var fxhashVersion: String? {
        guard isFxhash else { return nil }
        let lower = contract.lowercased()
        if lower.contains("kea8z") { return "v1 Vanilla" }
        if lower.contains("u6ehm") { return "v2" }
        if lower.contains("efsnu") { return "v3 (fx(params))" }
        return "fxhash"
    }

    /// The extracted project/collection name for an fxhash token (e.g. "Willie's Nightmare Cash Grab", "DOOMKATS")
    public var fxhashProjectName: String? {
        guard isFxhash else { return nil }
        if let proj = rawMetadata?["projectName"] ?? rawMetadata?["project_name"], !proj.isEmpty {
            return proj
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[WAITING TO BE SIGNED]" {
            return "fxhash (Pending Reveal)"
        }
        if let hashRange = trimmed.range(of: " #", options: .backwards) {
            let candidate = String(trimmed[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return candidate
            }
        }
        return nil
    }

    /// The extracted iteration string for an fxhash token (e.g. "284")
    public var fxhashIteration: String? {
        guard isFxhash else { return nil }
        if let iter = rawMetadata?["iteration"], !iter.isEmpty {
            return iter
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hashRange = trimmed.range(of: " #", options: .backwards) {
            let candidate = String(trimmed[hashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let slashRange = candidate.range(of: "/") {
                return String(candidate[..<slashRange.lowerBound])
            }
            return candidate
        }
        return nil
    }

    /// The issuer/project ID on fxhash & objkt (e.g. "19634", "30166")
    public var fxhashProjectId: String? {
        return rawMetadata?["issuer_id"] ?? rawMetadata?["projectId"] ?? rawMetadata?["project_id"]
    }

    /// Canonical objkt.com token URL (e.g. https://objkt.com/tokens/fxhash/1611331)
    public var objktTokenURL: URL? {
        if isFxhash {
            return URL(string: "https://objkt.com/tokens/fxhash/\(tokenId)")
        }
        return URL(string: "https://objkt.com/tokens/\(contract)/\(tokenId)")
    }

    /// Canonical objkt.com collection or project URL (e.g. https://objkt.com/collections/fxhash/projects/19634)
    public func objktCollectionURL(projectId: String? = nil) -> URL? {
        let pId = projectId ?? fxhashProjectId
        if isFxhash, let pId = pId, !pId.isEmpty {
            return URL(string: "https://objkt.com/collections/fxhash/projects/\(pId)")
        }
        return URL(string: "https://objkt.com/collections/\(contract)")
    }

    /// Canonical fxhash.xyz gentk URL
    public var fxhashGentkURL: URL? {
        guard isFxhash else { return nil }
        return URL(string: "https://www.fxhash.xyz/gentk/\(tokenId)")
    }

    /// Canonical fxhash.xyz project URL
    public func fxhashProjectURL(projectId: String? = nil) -> URL? {
        guard isFxhash else { return nil }
        let pId = projectId ?? fxhashProjectId
        if let pId = pId, !pId.isEmpty {
            return URL(string: "https://www.fxhash.xyz/generative/slug/\(pId)")
        }
        return URL(string: "https://www.fxhash.xyz")
    }
}
