import Foundation

/// Repository data state container
public struct RepositoryState: Codable, Sendable {
    public var sources: [WalletSource]
    public var whitelistedIds: Set<String>
    public var blacklistedIds: Set<String>
    public var tokens: [UnifiedToken]

    public init(
        sources: [WalletSource] = [],
        whitelistedIds: Set<String> = [],
        blacklistedIds: Set<String> = [],
        tokens: [UnifiedToken] = []
    ) {
        self.sources = sources
        self.whitelistedIds = whitelistedIds
        self.blacklistedIds = blacklistedIds
        self.tokens = tokens
    }
}

/// Actor managing local file-based persistence for user sources, preferences, and token index
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
        // Prevent duplicate addresses / curations
        if !state.sources.contains(where: { $0.id == source.id || $0.displayName == source.displayName }) {
            state.sources.append(source)
            try persist()
        }
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
            tokenMap[token.id] = token
        }
        state.tokens = Array(tokenMap.values)
        try persist()
    }

    public func clearTokens() async throws {
        state.tokens.removeAll()
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
