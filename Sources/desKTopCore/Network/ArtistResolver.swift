import Foundation

/// Resolved artist identity profile containing human-readable aliases, domain, social links, and bio
public struct ArtistProfile: Codable, Hashable, Sendable {
    public let address: String
    public let alias: String?
    public let tzdomain: String?
    public let twitter: String?
    public let website: String?
    public let description: String?
    public let logoUri: String?

    public init(
        address: String,
        alias: String? = nil,
        tzdomain: String? = nil,
        twitter: String? = nil,
        website: String? = nil,
        description: String? = nil,
        logoUri: String? = nil
    ) {
        self.address = address
        self.alias = alias
        self.tzdomain = tzdomain
        self.twitter = twitter
        self.website = website
        self.description = description
        self.logoUri = logoUri
    }

    public var displayName: String {
        if let a = alias?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            return a
        }
        if let d = tzdomain?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        guard address.count > 10 else { return address }
        return String(address.prefix(6)) + "…" + String(address.suffix(4))
    }

    public var twitterHandle: String? {
        guard let tw = twitter?.trimmingCharacters(in: .whitespacesAndNewlines), !tw.isEmpty else { return nil }
        if tw.hasPrefix("https://x.com/") {
            let handle = tw.replacingOccurrences(of: "https://x.com/", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "@\(handle)"
        }
        if tw.hasPrefix("https://twitter.com/") {
            let handle = tw.replacingOccurrences(of: "https://twitter.com/", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "@\(handle)"
        }
        if tw.hasPrefix("@") {
            return tw
        }
        return "@\(tw)"
    }

    public var twitterURL: URL? {
        guard let tw = twitter?.trimmingCharacters(in: .whitespacesAndNewlines), !tw.isEmpty else { return nil }
        if tw.hasPrefix("http://") || tw.hasPrefix("https://") {
            return URL(string: tw)
        }
        let handle = tw.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return URL(string: "https://x.com/\(handle)")
    }

    public var websiteURL: URL? {
        guard let site = website?.trimmingCharacters(in: .whitespacesAndNewlines), !site.isEmpty else { return nil }
        if site.hasPrefix("http://") || site.hasPrefix("https://") {
            return URL(string: site)
        }
        return URL(string: "https://\(site)")
    }

    public var objktProfileURL: URL? {
        return URL(string: "https://objkt.com/users/\(address)")
    }

    public var tzktProfileURL: URL? {
        return URL(string: "https://tzkt.io/\(address)")
    }
}

/// Actor responsible for resolving Tezos creator/artist wallet addresses (tz1, tz2, tz3, KT1)
/// to verified aliases, Tezos Domains (.tez), social accounts, and profile descriptions.
public actor ArtistResolver {
    public static let shared = ArtistResolver()

    private let objktEndpoint = URL(string: "https://data.objkt.com/v3/graphql")!
    private let tzktAccountsEndpoint = URL(string: "https://api.tzkt.io/v1/accounts")!
    private let session: URLSession

    private var cache: [String: ArtistProfile] = [:]
    private var cacheFileURL: URL?

    /// Synchronously loads all cached artist profiles from persistent disk or application bundle
    public static func loadCachedProfiles() -> [String: ArtistProfile] {
        var profiles: [String: ArtistProfile] = [:]

        // 1. Try bundled cache in Resources
        if let bundleURL = Bundle.main.url(forResource: "artists_cache", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let loaded = try? JSONDecoder().decode([String: ArtistProfile].self, from: data) {
            for (k, v) in loaded {
                profiles[k.lowercased()] = v
            }
        }

        // 2. Try persistent cache in Application Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = appSupport.appendingPathComponent("desKTop/artists_cache.json")
            if let data = try? Data(contentsOf: fileURL),
               let loaded = try? JSONDecoder().decode([String: ArtistProfile].self, from: data) {
                for (k, v) in loaded {
                    profiles[k.lowercased()] = v
                }
            }
        }

        return profiles
    }

    public init(session: URLSession = .shared) {
        self.session = session
        self.cache = Self.loadCachedProfiles()

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("desKTop", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.cacheFileURL = dir.appendingPathComponent("artists_cache.json")
        }
    }

    /// Resolves profiles for a collection of wallet addresses, returning cached and newly fetched profiles
    public func resolveArtists(for addresses: [String]) async -> [String: ArtistProfile] {
        var results: [String: ArtistProfile] = [:]
        var toFetch: [String] = []

        for addr in addresses {
            let lower = addr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty else { continue }
            if let cached = cache[lower] {
                results[addr] = cached
                results[lower] = cached
            } else {
                toFetch.append(addr)
            }
        }

        guard !toFetch.isEmpty else { return results }

        // Fetch in batches of 60 via Objkt GraphQL
        let chunks = stride(from: 0, to: toFetch.count, by: 60).map {
            Array(toFetch[$0..<min($0 + 60, toFetch.count)])
        }

        var missingFromObjkt: [String] = []

        for chunk in chunks {
            do {
                let fetched = try await fetchFromObjkt(addresses: chunk)
                for (addr, profile) in fetched {
                    results[addr] = profile
                    cache[addr.lowercased()] = profile
                }
                for a in chunk {
                    if fetched[a] == nil && fetched[a.lowercased()] == nil {
                        missingFromObjkt.append(a)
                    }
                }
            } catch {
                missingFromObjkt.append(contentsOf: chunk)
            }
        }

        // Fallback to TzKT accounts for any missing
        if !missingFromObjkt.isEmpty {
            let tzktChunks = stride(from: 0, to: missingFromObjkt.count, by: 40).map {
                Array(missingFromObjkt[$0..<min($0 + 40, missingFromObjkt.count)])
            }
            for chunk in tzktChunks {
                if let tzktFetched = try? await fetchFromTzKT(addresses: chunk) {
                    for (addr, profile) in tzktFetched {
                        results[addr] = profile
                        cache[addr.lowercased()] = profile
                    }
                }
            }
        }

        persistCache()
        return results
    }

    private func fetchFromObjkt(addresses: [String]) async throws -> [String: ArtistProfile] {
        let addrsLiteral = addresses.map { "\"\($0)\"" }.joined(separator: ", ")
        let query = """
        query ResolveHolders {
          holder(where: { address: { _in: [\(addrsLiteral)] } }) {
            address
            alias
            description
            logo
            twitter
            website
            tzdomain
          }
        }
        """

        var request = URLRequest(url: objktEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return [:]
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let holders = dataDict["holder"] as? [[String: Any]] else {
            return [:]
        }

        var map: [String: ArtistProfile] = [:]
        for h in holders {
            guard let address = h["address"] as? String else { continue }
            let alias = h["alias"] as? String
            let tzdomain = h["tzdomain"] as? String
            let twitter = h["twitter"] as? String
            let website = h["website"] as? String
            let description = h["description"] as? String
            let logo = h["logo"] as? String

            let profile = ArtistProfile(
                address: address,
                alias: alias,
                tzdomain: tzdomain,
                twitter: twitter,
                website: website,
                description: description,
                logoUri: logo
            )
            map[address] = profile
            map[address.lowercased()] = profile
        }
        return map
    }

    private func fetchFromTzKT(addresses: [String]) async throws -> [String: ArtistProfile] {
        guard var components = URLComponents(url: tzktAccountsEndpoint, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        components.queryItems = [
            URLQueryItem(name: "address.in", value: addresses.joined(separator: ",")),
            URLQueryItem(name: "select", value: "address,alias,extras")
        ]
        guard let url = components.url else { return [:] }

        var request = URLRequest(url: url)
        request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return [:]
        }

        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }

        var map: [String: ArtistProfile] = [:]
        for item in list {
            guard let addr = item["address"] as? String else { continue }
            let alias = item["alias"] as? String
            var twitter: String? = nil
            var website: String? = nil
            var description: String? = nil

            if let extras = item["extras"] as? [String: Any],
               let profile = extras["profile"] as? [String: Any] {
                twitter = profile["twitter"] as? String
                website = profile["site"] as? String
                description = profile["description"] as? String
            }

            let p = ArtistProfile(
                address: addr,
                alias: alias,
                tzdomain: alias?.hasSuffix(".tez") == true ? alias : nil,
                twitter: twitter,
                website: website,
                description: description
            )
            map[addr] = p
            map[addr.lowercased()] = p
        }
        return map
    }

    private func persistCache() {
        guard let fileURL = cacheFileURL else { return }
        try? JSONEncoder().encode(cache).write(to: fileURL)
    }
}
