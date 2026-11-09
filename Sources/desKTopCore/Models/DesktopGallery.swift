import Foundation

import Foundation

/// Gallery kind: curated static list of tokens vs dynamic smart filter rules
public enum GalleryType: String, Codable, Sendable {
    case manual // Hand-picked individual pieces
    case smart  // Live dynamic rule-based criteria (auto-updates with new mints & library syncs)
}

/// Follow scope when tracking a specific wallet or creator
public enum WalletFollowScope: String, Codable, Sendable {
    case created // Artworks created/minted by this wallet
    case owned   // Artworks collected/held by this wallet
}

/// Dynamic filter rules for a Smart Gallery
public struct GalleryFilterCriteria: Hashable, Codable, Sendable {
    public var searchText: String?
    public var formatFilter: String?
    public var collectionKey: String?
    public var sourceScope: String?            // "all", "owned", "created"
    public var targetWallet: String?           // Wallet address or .tez domain being followed
    public var walletScope: WalletFollowScope? // .created vs .owned
    public var sortOption: String?
    public var sortDirection: String?

    public init(
        searchText: String? = nil,
        formatFilter: String? = nil,
        collectionKey: String? = nil,
        sourceScope: String? = nil,
        targetWallet: String? = nil,
        walletScope: WalletFollowScope? = nil,
        sortOption: String? = nil,
        sortDirection: String? = nil
    ) {
        self.searchText = searchText
        self.formatFilter = formatFilter
        self.collectionKey = collectionKey
        self.sourceScope = sourceScope
        self.targetWallet = targetWallet
        self.walletScope = walletScope
        self.sortOption = sortOption
        self.sortDirection = sortDirection
    }

    /// Evaluates if a given token matches these dynamic filter criteria
    public func matches(token: UnifiedToken, artistDisplayName: (String) -> String = { $0 }) -> Bool {
        // 1. Search text filter
        if let query = searchText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty {
            let nameMatch = token.name.lowercased().contains(query)
            let descMatch = token.description?.lowercased().contains(query) ?? false
            let idMatch = token.tokenId.lowercased().contains(query) || token.contract.lowercased().contains(query)
            let creatorMatch = token.creators.contains { c in
                c.lowercased().contains(query) || artistDisplayName(c).lowercased().contains(query)
            }
            if !nameMatch && !descMatch && !idMatch && !creatorMatch {
                return false
            }
        }

        // 2. Format filter
        if let fmt = formatFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !fmt.isEmpty {
            let lowerFmt = fmt.lowercased()
            if lowerFmt != "all" && lowerFmt != "all formats" {
                switch lowerFmt {
                case "animated gifs", "animated gif", "gif", "animated":
                    if token.mediaCategory != .animatedImage { return false }
                case "video", "videos":
                    if token.mediaCategory != .video { return false }
                case "interactive html", "interactive", "html":
                    if token.mediaCategory != .interactiveHtml { return false }
                case "generative", "fxhash":
                    if token.mediaCategory != .fxhash { return false }
                case "aleatory":
                    if token.mediaCategory != .aleatory { return false }
                case "bytecode", "bootloader":
                    if token.mediaCategory != .bootloader { return false }
                case "static image", "image", "images", "stills":
                    if token.mediaCategory != .staticImage && token.mediaCategory != .vectorImage { return false }
                case "3d / audio", "3d", "audio":
                    if token.mediaCategory != .audio3d { return false }
                default:
                    break
                }
            }
        }

        // 3. Collection filter
        if let col = collectionKey?.trimmingCharacters(in: .whitespacesAndNewlines), !col.isEmpty {
            let lowerCol = col.lowercased()
            if lowerCol.hasPrefix("fxhash:") {
                let targetProj = String(lowerCol.dropFirst(7))
                if !token.isFxhash || (token.fxhashProjectName ?? "").lowercased() != targetProj {
                    return false
                }
            } else if token.contract.lowercased() != lowerCol {
                return false
            }
        }

        // 4. Source / Ownership Scope filter
        if let scope = sourceScope?.lowercased(), !scope.isEmpty {
            if scope == "owned" && !token.isOwned { return false }
            if scope == "created" && !token.isCreated { return false }
        }

        // 5. Target Wallet Follower (Created or Owned)
        if let wallet = targetWallet?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !wallet.isEmpty {
            let scope = walletScope ?? .created
            if scope == .created {
                let matchesCreator = token.creators.contains { c in
                    let cLower = c.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let alias = artistDisplayName(c).lowercased()
                    return cLower == wallet || cLower.contains(wallet) || wallet.contains(cLower) || alias == wallet || alias.contains(wallet)
                }
                if !matchesCreator { return false }
            } else if scope == .owned {
                let sourceMatch = (token.rawMetadata?["sourceWallet"]?.lowercased() == wallet)
                if !token.isOwned && !sourceMatch { return false }
            }
        }

        return true
    }
}

/// User-defined desktop wallpaper gallery / playlist (Supports hand-curated items and dynamic smart rules)
public struct DesktopGallery: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var type: GalleryType
    public var tokenIds: [String]
    public var criteria: GalleryFilterCriteria?
    public var isActiveForRotation: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public var isSmart: Bool {
        return type == .smart || criteria != nil
    }

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        type: GalleryType = .manual,
        tokenIds: [String] = [],
        criteria: GalleryFilterCriteria? = nil,
        isActiveForRotation: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = (criteria != nil) ? .smart : type
        self.tokenIds = tokenIds
        self.criteria = criteria
        self.isActiveForRotation = isActiveForRotation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, tokenIds, criteria, isActiveForRotation, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        let decodedCriteria = try container.decodeIfPresent(GalleryFilterCriteria.self, forKey: .criteria)
        self.criteria = decodedCriteria
        if let explicitType = try container.decodeIfPresent(GalleryType.self, forKey: .type) {
            self.type = explicitType
        } else {
            self.type = (decodedCriteria != nil) ? .smart : .manual
        }
        self.tokenIds = try container.decodeIfPresent([String].self, forKey: .tokenIds) ?? []
        self.isActiveForRotation = try container.decodeIfPresent(Bool.self, forKey: .isActiveForRotation) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// Evaluates which tokens belong in this gallery (either by static tokenIds or dynamic criteria matching)
    public func matchingTokens(from allTokens: [UnifiedToken], artistDisplayName: (String) -> String = { $0 }) -> [UnifiedToken] {
        if isSmart, let criteria = criteria {
            return allTokens.filter { criteria.matches(token: $0, artistDisplayName: artistDisplayName) }
        }
        let idSet = Set(tokenIds)
        return allTokens.filter { idSet.contains($0.id) }
    }
}
