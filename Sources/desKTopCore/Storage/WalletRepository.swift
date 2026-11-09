import Foundation

public enum CollectionRotationScope: String, Codable, Hashable, Sendable {
    case inLibrary = "inLibrary"
    case entireCollection = "entireCollection"

    public var displayName: String {
        switch self {
        case .inLibrary: return "My Pieces"
        case .entireCollection: return "Entire Collection"
        }
    }
}

public enum ActiveRotationTarget: Hashable, Sendable {
    case allArt
    case owned
    case created
    case collection(contract: String, displayName: String, scope: CollectionRotationScope = .inLibrary)
    case customGallery(id: UUID, name: String)
    case objktCuration(id: String, name: String)

    public var displayName: String {
        switch self {
        case .allArt: return "All Art"
        case .owned: return "Owned Art"
        case .created: return "Created Art"
        case .collection(_, let name, let scope):
            return scope == .entireCollection ? "Entire \(name)" : "My \(name)"
        case .customGallery(_, let name): return name
        case .objktCuration(_, let name): return name
        }
    }

    public var isCollection: Bool {
        if case .collection = self { return true }
        return false
    }

    public var collectionContract: String? {
        if case .collection(let c, _, _) = self { return c }
        return nil
    }

    public var collectionScope: CollectionRotationScope? {
        if case .collection(_, _, let s) = self { return s }
        return nil
    }
}

private struct EmptyCodable: Codable {}

extension ActiveRotationTarget: Codable {
    enum CodingKeys: String, CodingKey {
        case allArt, owned, created, collection, customGallery, objktCuration
    }

    enum CollectionKeys: String, CodingKey {
        case contract, displayName, scope
    }

    enum CustomGalleryKeys: String, CodingKey {
        case id, name
    }

    enum ObjktCurationKeys: String, CodingKey {
        case id, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.allArt) {
            self = .allArt
        } else if container.contains(.owned) {
            self = .owned
        } else if container.contains(.created) {
            self = .created
        } else if container.contains(.collection) {
            let colContainer = try container.nestedContainer(keyedBy: CollectionKeys.self, forKey: .collection)
            let contract = try colContainer.decode(String.self, forKey: .contract)
            let displayName = try colContainer.decode(String.self, forKey: .displayName)
            let scope = try colContainer.decodeIfPresent(CollectionRotationScope.self, forKey: .scope) ?? .inLibrary
            self = .collection(contract: contract, displayName: displayName, scope: scope)
        } else if container.contains(.customGallery) {
            let gContainer = try container.nestedContainer(keyedBy: CustomGalleryKeys.self, forKey: .customGallery)
            let id = try gContainer.decode(UUID.self, forKey: .id)
            let name = try gContainer.decode(String.self, forKey: .name)
            self = .customGallery(id: id, name: name)
        } else if container.contains(.objktCuration) {
            let oContainer = try container.nestedContainer(keyedBy: ObjktCurationKeys.self, forKey: .objktCuration)
            let id = try oContainer.decode(String.self, forKey: .id)
            let name = try oContainer.decode(String.self, forKey: .name)
            self = .objktCuration(id: id, name: name)
        } else {
            self = .allArt
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allArt:
            try container.encode(EmptyCodable(), forKey: .allArt)
        case .owned:
            try container.encode(EmptyCodable(), forKey: .owned)
        case .created:
            try container.encode(EmptyCodable(), forKey: .created)
        case .collection(let contract, let displayName, let scope):
            var colContainer = container.nestedContainer(keyedBy: CollectionKeys.self, forKey: .collection)
            try colContainer.encode(contract, forKey: .contract)
            try colContainer.encode(displayName, forKey: .displayName)
            try colContainer.encode(scope, forKey: .scope)
        case .customGallery(let id, let name):
            var gContainer = container.nestedContainer(keyedBy: CustomGalleryKeys.self, forKey: .customGallery)
            try gContainer.encode(id, forKey: .id)
            try gContainer.encode(name, forKey: .name)
        case .objktCuration(let id, let name):
            var oContainer = container.nestedContainer(keyedBy: ObjktCurationKeys.self, forKey: .objktCuration)
            try oContainer.encode(id, forKey: .id)
            try oContainer.encode(name, forKey: .name)
        }
    }
}

extension Notification.Name {
    public static let didChangeActiveRotation = Notification.Name("desKTop.didChangeActiveRotation")
    public static let didRequestNextWallpaper = Notification.Name("desKTop.didRequestNextWallpaper")
}

/// Repository data state container
public struct RepositoryState: Codable, Sendable {
    public var sources: [WalletSource]
    public var whitelistedIds: Set<String>
    public var blacklistedIds: Set<String>
    public var tokens: [UnifiedToken]
    public var galleries: [DesktopGallery]
    public var objktCurations: [ObjktGallerySummary]
    public var activeRotationTarget: ActiveRotationTarget?
    public var isRotationPaused: Bool
    public var isRotationShuffle: Bool
    public var rotationIntervalSeconds: Int

    public init(
        sources: [WalletSource] = [],
        whitelistedIds: Set<String> = [],
        blacklistedIds: Set<String> = [],
        tokens: [UnifiedToken] = [],
        galleries: [DesktopGallery] = [],
        objktCurations: [ObjktGallerySummary] = [],
        activeRotationTarget: ActiveRotationTarget? = .allArt,
        isRotationPaused: Bool = false,
        isRotationShuffle: Bool = true,
        rotationIntervalSeconds: Int = 300
    ) {
        self.sources = sources
        self.whitelistedIds = whitelistedIds
        self.blacklistedIds = blacklistedIds
        self.tokens = tokens
        self.galleries = galleries
        self.objktCurations = objktCurations
        self.activeRotationTarget = activeRotationTarget
        self.isRotationPaused = isRotationPaused
        self.isRotationShuffle = isRotationShuffle
        self.rotationIntervalSeconds = rotationIntervalSeconds
    }

    enum CodingKeys: String, CodingKey {
        case sources, whitelistedIds, blacklistedIds, tokens, galleries, objktCurations,
             activeRotationTarget, isRotationPaused, isRotationShuffle, rotationIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sources = try container.decodeIfPresent([WalletSource].self, forKey: .sources) ?? []
        self.whitelistedIds = try container.decodeIfPresent(Set<String>.self, forKey: .whitelistedIds) ?? []
        self.blacklistedIds = try container.decodeIfPresent(Set<String>.self, forKey: .blacklistedIds) ?? []
        self.tokens = try container.decodeIfPresent([UnifiedToken].self, forKey: .tokens) ?? []
        self.galleries = try container.decodeIfPresent([DesktopGallery].self, forKey: .galleries) ?? []
        self.objktCurations = try container.decodeIfPresent([ObjktGallerySummary].self, forKey: .objktCurations) ?? []
        self.activeRotationTarget = try container.decodeIfPresent(ActiveRotationTarget.self, forKey: .activeRotationTarget) ?? .allArt
        self.isRotationPaused = try container.decodeIfPresent(Bool.self, forKey: .isRotationPaused) ?? false
        self.isRotationShuffle = try container.decodeIfPresent(Bool.self, forKey: .isRotationShuffle) ?? true
        self.rotationIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .rotationIntervalSeconds) ?? 300
    }

    public mutating func markCreatedTokens() {
        var sourceAddresses: Set<String> = []
        for s in sources {
            if let addr = s.walletAddress {
                sourceAddresses.insert(addr.lowercased())
            }
        }
        guard !sourceAddresses.isEmpty else { return }
        for i in 0..<tokens.count {
            if !tokens[i].isCreated {
                let isCreator = tokens[i].creators.contains { c in
                    sourceAddresses.contains(c.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                }
                if isCreator {
                    tokens[i].isCreated = true
                }
            }
        }
    }
}

/// Actor managing local file-based persistence for user sources, preferences, custom galleries, and token index
public actor WalletRepository {
    private let storageURL: URL
    private let fullCollectionCacheURL: URL
    private var state: RepositoryState
    private var fullCollectionCache: [String: [UnifiedToken]] = [:]

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
        self.fullCollectionCacheURL = directory.appendingPathComponent("collection_tokens_cache.json")

        // Load existing state if available
        if let data = try? Data(contentsOf: storageURL),
           var loaded = try? JSONDecoder().decode(RepositoryState.self, from: data) {
            loaded.markCreatedTokens()
            self.state = loaded
        } else {
            self.state = RepositoryState()
        }

        // Load cached entire collections
        if let cacheData = try? Data(contentsOf: fullCollectionCacheURL),
           let loadedCache = try? JSONDecoder().decode([String: [UnifiedToken]].self, from: cacheData) {
            self.fullCollectionCache = loadedCache
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
        state.markCreatedTokens()
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

    public func createSmartGallery(name: String, description: String? = nil, criteria: GalleryFilterCriteria) async throws -> DesktopGallery {
        let gallery = DesktopGallery(name: name, description: description, type: .smart, tokenIds: [], criteria: criteria)
        state.galleries.append(gallery)
        try persist()
        return gallery
    }

    public func createManualGallery(name: String, description: String? = nil, tokenIds: [String]) async throws -> DesktopGallery {
        let gallery = DesktopGallery(name: name, description: description, type: .manual, tokenIds: tokenIds, criteria: nil)
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
        if let id = id, let g = state.galleries.first(where: { $0.id == id }) {
            state.activeRotationTarget = .customGallery(id: g.id, name: g.name)
        } else {
            state.activeRotationTarget = .allArt
        }
        try persist()
        await MainActor.run {
            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
        }
    }

    // MARK: - Active Rotation Management

    public func getActiveRotationTarget() -> ActiveRotationTarget {
        return state.activeRotationTarget ?? .allArt
    }

    public func setActiveRotationTarget(_ target: ActiveRotationTarget) async throws {
        state.activeRotationTarget = target
        for idx in state.galleries.indices {
            if case .customGallery(let gid, _) = target {
                state.galleries[idx].isActiveForRotation = (state.galleries[idx].id == gid)
            } else {
                state.galleries[idx].isActiveForRotation = false
            }
        }
        try persist()
        await MainActor.run {
            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
        }
    }

    public func isRotationPaused() -> Bool {
        return state.isRotationPaused
    }

    public func setRotationPaused(_ paused: Bool) async throws {
        state.isRotationPaused = paused
        try persist()
        await MainActor.run {
            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
        }
    }

    public func isRotationShuffle() -> Bool {
        return state.isRotationShuffle
    }

    public func setRotationShuffle(_ shuffle: Bool) async throws {
        state.isRotationShuffle = shuffle
        try persist()
    }

    public func getRotationInterval() -> Int {
        return state.rotationIntervalSeconds
    }

    public func setRotationInterval(_ seconds: Int) async throws {
        state.rotationIntervalSeconds = seconds
        try persist()
        await MainActor.run {
            NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
        }
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

    /// Tokens to use for wallpaper rotation according to the active rotation target
    public func getActiveRotationTokens() -> [UnifiedToken] {
        let target = state.activeRotationTarget ?? .allArt
        switch target {
        case .allArt:
            return state.tokens
        case .owned:
            return state.tokens.filter { !$0.isCreated }
        case .created:
            return state.tokens.filter { $0.isCreated }
        case .collection(let contract, _, let scope):
            if scope == .entireCollection {
                if let full = fullCollectionCache[contract] ?? fullCollectionCache[contract.lowercased()], !full.isEmpty {
                    return full
                }
            }
            let matching: [UnifiedToken]
            if contract.hasPrefix("fxhash:") {
                let proj = String(contract.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                matching = state.tokens.filter { $0.isFxhash && (($0.fxhashProjectName?.lowercased() == proj) || $0.name.lowercased().hasPrefix(proj)) }
            } else {
                matching = state.tokens.filter { $0.contract.caseInsensitiveCompare(contract) == .orderedSame }
            }
            return matching.isEmpty ? state.tokens : matching
        case .customGallery(let gid, _):
            guard let g = state.galleries.first(where: { $0.id == gid }) else {
                return state.tokens
            }
            let matched = g.matchingTokens(from: state.tokens)
            return matched.isEmpty ? state.tokens : matched
        case .objktCuration(let cid, _):
            let matched = state.tokens.filter { $0.rawMetadata?["curationId"] == cid }
            return matched.isEmpty ? state.tokens : matched
        }
    }

    // MARK: - Full Collection Token Cache

    public func getFullCollectionTokens(key: String) -> [UnifiedToken]? {
        return fullCollectionCache[key] ?? fullCollectionCache[key.lowercased()]
    }

    public func setFullCollectionTokens(key: String, tokens: [UnifiedToken]) async throws {
        fullCollectionCache[key] = tokens
        fullCollectionCache[key.lowercased()] = tokens
        persistFullCollectionCache()
        if case .collection(let activeContract, _, let scope) = state.activeRotationTarget,
           activeContract.caseInsensitiveCompare(key) == .orderedSame,
           scope == .entireCollection {
            await MainActor.run {
                NotificationCenter.default.post(name: .didChangeActiveRotation, object: nil)
            }
        }
    }

    private func persistFullCollectionCache() {
        if let data = try? JSONEncoder().encode(fullCollectionCache) {
            try? data.write(to: fullCollectionCacheURL, options: .atomic)
        }
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
