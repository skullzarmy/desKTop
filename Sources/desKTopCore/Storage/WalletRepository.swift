import Foundation

/// Repository data state container
public struct RepositoryState: Codable, Sendable {
    public var sources: [WalletSource]
    public var whitelistedIds: Set<String>
    public var blacklistedIds: Set<String>
    public var tokens: [UnifiedToken]
    public var galleries: [DesktopGallery]
    public var objktCurations: [ObjktGallerySummary]

    public init(
        sources: [WalletSource] = [],
        whitelistedIds: Set<String> = [],
        blacklistedIds: Set<String> = [],
        tokens: [UnifiedToken] = [],
        galleries: [DesktopGallery] = [],
        objktCurations: [ObjktGallerySummary] = []
    ) {
        self.sources = sources
        self.whitelistedIds = whitelistedIds
        self.blacklistedIds = blacklistedIds
        self.tokens = tokens
        self.galleries = galleries
        self.objktCurations = objktCurations
    }
}

/// Actor managing local file-based persistence for user sources, preferences, custom galleries, and token index
public actor WalletRepository {
    private let storageURL: URL
    private var state: RepositoryState

    public init(storageDirectory: URL? = nil) {
        let directory: URL
        if let customDir = storageDirectory {
            directory = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            directory = appSupport.appendingPathComponent("desKTop", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent("library.json")

        // Load existing state if available
        if let data = try? Data(contentsOf: storageURL),
           let loaded = try? JSONDecoder().decode(RepositoryState.self, from: data) {
            self.state = loaded
        } else {
            self.state = RepositoryState()
        }
    }

    // MARK: - Source Management (CRUD)

    public func getSources() -> [WalletSource] {
        return state.sources
    }

    public func addSource(_ source: WalletSource) async throws {
        if let idx = state.sources.firstIndex(where: { $0.id == source.id || $0.displayName == source.displayName }) {
            state.sources[idx] = source
        } else {
            state.sources.append(source)
        }
        try persist()
    }

    public func updateSource(_ source: WalletSource) async throws {
        if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
            state.sources[index] = source
            try persist()
        }
    }

    public func removeSource(id: UUID) async throws {
        state.sources.removeAll(where: { $0.id == id })
        try persist()
    }

    // MARK: - Whitelist & Blacklist

    public func getWhitelist() -> Set<String> {
        return state.whitelistedIds
    }

    public func getBlacklist() -> Set<String> {
        return state.blacklistedIds
    }

    public func whitelistToken(id: String) async throws {
        state.whitelistedIds.insert(id)
        state.blacklistedIds.remove(id)
        try persist()
    }

    public func blacklistToken(id: String) async throws {
        state.blacklistedIds.insert(id)
        state.whitelistedIds.remove(id)
        try persist()
    }

    // MARK: - Token Index Cache

    public func getTokens() -> [UnifiedToken] {
        return state.tokens
    }

    public func upsertTokens(_ newTokens: [UnifiedToken]) async throws {
        var tokenMap: [String: UnifiedToken] = [:]
        for existing in state.tokens {
            tokenMap[existing.id] = existing
        }
        for token in newTokens {
            if let existing = tokenMap[token.id] {
                var updated = token
                updated.isOwned = existing.isOwned || token.isOwned
                updated.isCreated = existing.isCreated || token.isCreated
                tokenMap[token.id] = updated
            } else {
                tokenMap[token.id] = token
            }
        }
        state.tokens = Array(tokenMap.values)
        try persist()
    }

    public func clearTokens() async throws {
        state.tokens.removeAll()
        try persist()
    }

    // MARK: - desKTop Galleries

    public func getGalleries() -> [DesktopGallery] {
        return state.galleries
    }

    public func createGallery(name: String, description: String? = nil) async throws -> DesktopGallery {
        let gallery = DesktopGallery(name: name, description: description)
        state.galleries.append(gallery)
        try persist()
        return gallery
    }

    public func updateGallery(_ gallery: DesktopGallery) async throws {
        if let idx = state.galleries.firstIndex(where: { $0.id == gallery.id }) {
            var g = gallery
            g.updatedAt = Date()
            state.galleries[idx] = g
            try persist()
        }
    }

    public func deleteGallery(id: UUID) async throws {
        state.galleries.removeAll(where: { $0.id == id })
        try persist()
    }

    public func setActiveGallery(id: UUID?) async throws {
        for i in 0..<state.galleries.count {
            state.galleries[i].isActiveForRotation = (state.galleries[i].id == id)
        }
        try persist()
    }

    public func addTokenToGallery(tokenId: String, galleryId: UUID) async throws {
        if let idx = state.galleries.firstIndex(where: { $0.id == galleryId }) {
            if !state.galleries[idx].tokenIds.contains(tokenId) {
                state.galleries[idx].tokenIds.append(tokenId)
                state.galleries[idx].updatedAt = Date()
                try persist()
            }
        }
    }

    public func removeTokenFromGallery(tokenId: String, galleryId: UUID) async throws {
        if let idx = state.galleries.firstIndex(where: { $0.id == galleryId }) {
            state.galleries[idx].tokenIds.removeAll(where: { $0 == tokenId })
            state.galleries[idx].updatedAt = Date()
            try persist()
        }
    }

    /// Tokens to use for wallpaper rotation: if a custom gallery is set active, use its tokens; otherwise all tokens
    public func getActiveRotationTokens() -> [UnifiedToken] {
        if let activeGallery = state.galleries.first(where: { $0.isActiveForRotation }),
           !activeGallery.tokenIds.isEmpty {
            let activeSet = Set(activeGallery.tokenIds)
            let matched = state.tokens.filter { activeSet.contains($0.id) }
            if !matched.isEmpty {
                return matched
            }
        }
        return state.tokens
    }

    // MARK: - objkt Curations Cache

    public func getObjktCurations() -> [ObjktGallerySummary] {
        return state.objktCurations
    }

    public func setObjktCurations(_ curations: [ObjktGallerySummary]) async throws {
        state.objktCurations = curations
        try persist()
    }

    // MARK: - Persistence Helper

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: storageURL, options: .atomic)
    }
}
