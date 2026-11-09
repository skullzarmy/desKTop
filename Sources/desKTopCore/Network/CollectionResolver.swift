import Foundation

/// Resolves Tezos contract addresses (KT1...) to human-readable collection and project names
/// using Objkt.com GraphQL API, TzKT contract aliases, and a persistent cache.
public actor CollectionResolver {
    public static let shared = CollectionResolver()

    private let objktEndpoint = URL(string: "https://data.objkt.com/v3/graphql")!
    private let tzktContractsEndpoint = URL(string: "https://api.tzkt.io/v1/contracts")!
    private let session: URLSession

    private var cache: [String: String] = [:]
    private var cacheFileURL: URL?

    public init(session: URLSession = .shared) {
        self.session = session

        // Built-in well-known Tezos contracts
        self.cache = [
            "kt1rj6pbjhpwc3m5rw5s2nbmefwbuwbdxton": "hic et nunc",
            "kt1xacf6gkjfnkg3qmpfn6gep53momvjkj1e": "open objkt",
            "kt1kea8z6vwxdjrvqtmraedvzsvxat3khace": "fxhash GENTK v1",
            "kt1u6ehmng3rqgzgwrjvm31tymgwgymo61gk": "fxhash GENTK v2",
            "kt1u6ehmnxjtkvawj4thczg4fsdahc21ssvi": "fxhash GENTK v2",
            "kt1efsnuqwlacdq3maa3gkpjtrmmqqes2nuv": "fxhash GENTK v3 / fx(params)",
            "kt1efsnuqwlawdd3o4pvfux1cah5gmdtrrvr": "fx(params)",
            "kt1czvsa18hndyupv9ncxy3qj7p8yfdzkvqv": "Mooncakes",
            "kt1dck1a29voepg9mgcgowngenjv6etwpbyq": "Life List of an AI Birder",
            "kt1rg7tkpgj7z42rkdhjcjzfxggeqtaqnepp": "Just Failed Fantasy",
            "kt1ft6ypzbepauv6btjq21cmzjgtcpnqzmw": "WTF IS A HORSE?",
            "kt1ft6ypzbepauv6btjq21cmzjgtcpnzmwh": "WTF IS A HORSE?",
            "kt1svctvagpukmunevbfuxhk9ixckbpw5f13h": "Playing With Skulls",
            "kt1thfytvz3k1qhsy2v77kjmdrnjebzm3mzg": "Pepoles Advent Calendar",
            "kt1v15gktzmo7h9azgvwcbjqqnnjnzn1agsc": "Super Chumbino Tezos Club 2026",
            "kt1vlvgtw6ukwzmipan8sncomjicitqbgf6": "Long Story Short",
            "kt1gez9shjdsg4nmtdktpvjdic3cf3bkzupsc": "DOOMBUDS",
            "kt1htqeasguu2jxfqw1px2fgsvmw yks4r9pw": "Not",
            "kt1kvk31zfry3nxam6ng7vnnfanhkckjkqnq": "Treasure Chest",
            "kt1esyY1ltquwcxgtc7j72muccf2csqtglrh": "Welcome to the Land of Nightmares",
            "kt1gbzmsxmnkjxgmdmlbugpflyupmulsmwks": "Tezos Domains NameRegistry",
            "kt1vivwovfgscdaxjwoovejm1aysgz7s2tz": "Tezotopia NFT Registry",
            "kt1erkvqehg9jxgug2kglw3bnm7zxhx8sdf": "Tezotopia Resources",
            "kt1jagjc6ftj9szggits8gvoncr8cfp5hgv": "QuipuSwap MCH",
            "kt1phubmzpfdsvrbwbgvq3fqcewce9ectzeq": "Versum Items",
            "kt1mchcpyoagydsr8y4rpkrx7b7vokmndbbh": "Misfits",
            "kt1besvs34aj3kfxm2p7nu9qjfhhpv3rbg2p": "DEGENs",
            "kt1qzxwvvumxsqdpjnebzumthr7hq44fqrnn": "Summer Palms",
            "kt1rron7yf6yj7rm7afybc8zydvk3udxmupm": "TezTowers",
            "kt1st7grn4lwxb8y6bvgq8sdjgvqhd8sjghb": "Tez Frenz",
            "kt1cfdgefo44dn64jgtfhf2yqrzktkg1yfxm4": "House of Skratz"
        ]

        // Load disk cache if available
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("desKTop", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("collections_cache.json")
            self.cacheFileURL = fileURL

            if let data = try? Data(contentsOf: fileURL),
               let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
                for (k, v) in loaded {
                    self.cache[k.lowercased()] = v
                }
            }
        }
    }

    /// Resolves names for a batch of contract addresses
    public func resolveNames(for contracts: [String]) async -> [String: String] {
        var results: [String: String] = [:]
        var toFetch: [String] = []

        for c in contracts {
            let lower = c.lowercased()
            if let cached = cache[lower] {
                results[c] = cached
            } else {
                toFetch.append(c)
            }
        }

        guard !toFetch.isEmpty else { return results }

        // Fetch in batches of 40 from Objkt GraphQL
        let chunks = stride(from: 0, to: toFetch.count, by: 40).map {
            Array(toFetch[$0..<min($0 + 40, toFetch.count)])
        }

        var missingFromObjkt: [String] = []

        for chunk in chunks {
            do {
                let fetched = try await fetchFromObjkt(contracts: chunk)
                for (contract, name) in fetched {
                    results[contract] = name
                    cache[contract.lowercased()] = name
                }
                for c in chunk {
                    if fetched[c] == nil {
                        missingFromObjkt.append(c)
                    }
                }
            } catch {
                missingFromObjkt.append(contentsOf: chunk)
            }
        }

        // Fallback to TzKT contract aliases for any missing
        if !missingFromObjkt.isEmpty {
            let tzktChunks = stride(from: 0, to: missingFromObjkt.count, by: 30).map {
                Array(missingFromObjkt[$0..<min($0 + 30, missingFromObjkt.count)])
            }
            for chunk in tzktChunks {
                if let tzktFetched = try? await fetchFromTzKT(contracts: chunk) {
                    for (c, alias) in tzktFetched {
                        results[c] = alias
                        cache[c.lowercased()] = alias
                    }
                }
            }
        }

        // Save cache to disk
        persistCache()

        return results
    }

    private func fetchFromObjkt(contracts: [String]) async throws -> [String: String] {
        let query = """
        query ResolveCollections($contracts: [String!]!) {
          fa(where: { contract: { _in: $contracts } }) {
            contract
            name
            short_name
          }
        }
        """

        var request = URLRequest(url: objktEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "query": query,
            "variables": ["contracts": contracts]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return [:]
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let faList = dataDict["fa"] as? [[String: Any]] else {
            return [:]
        }

        var map: [String: String] = [:]
        for item in faList {
            guard let contract = item["contract"] as? String else { continue }
            let name = (item["name"] as? String) ?? (item["short_name"] as? String)
            if let validName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !validName.isEmpty {
                map[contract] = validName
            }
        }
        return map
    }

    private func fetchFromTzKT(contracts: [String]) async throws -> [String: String] {
        guard var components = URLComponents(url: tzktContractsEndpoint, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        components.queryItems = [
            URLQueryItem(name: "address.in", value: contracts.joined(separator: ",")),
            URLQueryItem(name: "select", value: "address,alias")
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

        var map: [String: String] = [:]
        for item in list {
            if let addr = item["address"] as? String,
               let alias = item["alias"] as? String,
               !alias.isEmpty {
                map[addr] = alias
            }
        }
        return map
    }

    private func persistCache() {
        guard let fileURL = cacheFileURL else { return }
        try? JSONEncoder().encode(cache).write(to: fileURL)
    }
}
