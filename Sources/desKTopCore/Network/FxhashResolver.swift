import Foundation

/// Resolved project metadata for an fxhash gentk token
public struct FxhashProjectInfo: Codable, Hashable, Sendable {
    public let contract: String
    public let tokenId: String
    public let issuerId: String       // e.g. "19634", "30166"
    public let iteration: String?     // e.g. "35", "284"
    public let projectName: String?   // e.g. "Beholders", "Willie's Nightmare Cash Grab"
    public let version: String        // "v1", "v2", "v3"

    public init(
        contract: String,
        tokenId: String,
        issuerId: String,
        iteration: String? = nil,
        projectName: String? = nil,
        version: String = "v2"
    ) {
        self.contract = contract
        self.tokenId = tokenId
        self.issuerId = issuerId
        self.iteration = iteration
        self.projectName = projectName
        self.version = version
    }

    public var objktProjectURL: URL? {
        guard !issuerId.isEmpty else { return nil }
        return URL(string: "https://objkt.com/collections/fxhash/projects/\(issuerId)")
    }

    public var objktTokenURL: URL? {
        guard !tokenId.isEmpty else { return nil }
        return URL(string: "https://objkt.com/tokens/fxhash/\(tokenId)")
    }

    public var fxhashProjectURL: URL? {
        guard !issuerId.isEmpty else { return nil }
        return URL(string: "https://www.fxhash.xyz/generative/slug/\(issuerId)")
    }

    public var fxhashGentkURL: URL? {
        guard !tokenId.isEmpty else { return nil }
        return URL(string: "https://www.fxhash.xyz/gentk/\(tokenId)")
    }
}

/// Actor responsible for resolving fxhash tokens across all 3 generations (v1 Vanilla, v2, v3 fx(params))
/// to their parent Generative Token Projects, issuer IDs, iterations, and canonical objkt/fxhash links.
public actor FxhashResolver {
    public static let shared = FxhashResolver()

    private let session: URLSession
    private var cache: [String: FxhashProjectInfo] = [:] // key: contract_tokenId
    private var cacheFileURL: URL?

    public static let fxhashContracts: Set<String> = [
        "kt1kea8z6vwxdjrvqtmraedvzsvxat3khace", // v1 Vanilla
        "kt1u6ehmnxjtkvawj4thczg4fsdahc21ssvi", // v2
        "kt1u6ehmng3rqgzgwrjvm31tymgwgymo61gk", // v2 alt
        "kt1efsnuqwlawdd3o4pvfux1cah5gmdtrrvr", // v3 fx(params)
        "kt1efsnuqwlacdq3maa3gkpjtrmmqqes2nuv"  // v3 alt
    ]

    public static func isFxhash(contract: String) -> Bool {
        return fxhashContracts.contains(contract.lowercased())
    }

    public static func fxhashVersion(for contract: String) -> String {
        let lower = contract.lowercased()
        if lower.contains("kea8z") { return "v1 Vanilla" }
        if lower.contains("u6ehm") { return "v2" }
        if lower.contains("efsnu") { return "v3 (fx(params))" }
        return "fxhash"
    }

    public static func loadCachedProjects() -> [String: FxhashProjectInfo] {
        var projects: [String: FxhashProjectInfo] = [:]

        // 1. Try loading bundled cache
        if let bundleURL = Bundle.main.url(forResource: "fxhash_cache", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let loaded = try? JSONDecoder().decode([String: FxhashProjectInfo].self, from: data) {
            for (k, v) in loaded {
                projects[k] = v
            }
        }

        // 2. Try loading persistent cache from Application Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = appSupport.appendingPathComponent("desKTop/fxhash_cache.json")
            if let data = try? Data(contentsOf: fileURL),
               let loaded = try? JSONDecoder().decode([String: FxhashProjectInfo].self, from: data) {
                for (k, v) in loaded {
                    projects[k] = v
                }
            }
        }

        return projects
    }

    public init(session: URLSession = .shared) {
        self.session = session
        self.cache = Self.loadCachedProjects()

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("desKTop", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheFileURL = dir.appendingPathComponent("fxhash_cache.json")
        }
    }

    public func getCachedInfo(contract: String, tokenId: String) -> FxhashProjectInfo? {
        let key = "\(contract)_\(tokenId)"
        return cache[key]
    }

    /// Resolves project info for an array of tokens, querying TzKT token_data bigmap in chunks
    public func resolveProjects(for tokens: [UnifiedToken]) async -> [String: FxhashProjectInfo] {
        var results: [String: FxhashProjectInfo] = [:]
        var missingByContract: [String: [(tokenId: String, name: String)]] = [:]

        for t in tokens {
            guard Self.isFxhash(contract: t.contract) else { continue }
            let key = "\(t.contract)_\(t.tokenId)"
            if let cached = cache[key] {
                results[key] = cached
            } else {
                missingByContract[t.contract, default: []].append((t.tokenId, t.name))
            }
        }

        guard !missingByContract.isEmpty else {
            return results
        }

        for (contract, list) in missingByContract {
            let version = Self.fxhashVersion(for: contract)
            let chunks = stride(from: 0, to: list.count, by: 40).map {
                Array(list[$0..<min($0 + 40, list.count)])
            }

            for chunk in chunks {
                let tokenIds = chunk.map(\.tokenId)
                let nameMap = Dictionary(uniqueKeysWithValues: chunk.map { ($0.tokenId, $0.name) })
                guard let url = URL(string: "https://api.tzkt.io/v1/contracts/\(contract)/bigmaps/token_data/keys?key.in=\(tokenIds.joined(separator: ","))&select=key,value") else {
                    continue
                }

                var request = URLRequest(url: url)
                request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

                guard let (data, response) = try? await session.data(for: request),
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
                    continue
                }

                for item in list {
                    guard let key = item["key"] as? String,
                          let val = item["value"] as? [String: Any],
                          let issuerId = val["issuer_id"] as? String else {
                        continue
                    }
                    let iteration = val["iteration"] as? String
                    let rawName = nameMap[key] ?? ""
                    let projectName = extractProjectName(from: rawName)

                    let info = FxhashProjectInfo(
                        contract: contract,
                        tokenId: key,
                        issuerId: issuerId,
                        iteration: iteration,
                        projectName: projectName,
                        version: version
                    )
                    let compKey = "\(contract)_\(key)"
                    cache[compKey] = info
                    results[compKey] = info
                }
            }
        }

        persistCache()
        return results
    }

    private func extractProjectName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[WAITING TO BE SIGNED]" {
            return "fxhash (Pending Reveal)"
        }
        if let range = trimmed.range(of: " #", options: .backwards) {
            let candidate = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return candidate
            }
        }
        return trimmed
    }

    private func persistCache() {
        guard let fileURL = cacheFileURL else { return }
        try? JSONEncoder().encode(cache).write(to: fileURL)
    }
}
