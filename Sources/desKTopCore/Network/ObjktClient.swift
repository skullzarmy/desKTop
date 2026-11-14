import Foundation

/// Summary of an objkt.com user curation / gallery
public struct ObjktGallerySummary: Identifiable, Hashable, Codable, Sendable {
    public var id: String { galleryId }
    public let galleryId: String
    public let slug: String
    public let name: String
    public let description: String?
    public let logoUri: String?
    public let itemsCount: Int

    public init(
        galleryId: String,
        slug: String,
        name: String,
        description: String? = nil,
        logoUri: String? = nil,
        itemsCount: Int = 0
    ) {
        self.galleryId = galleryId
        self.slug = slug
        self.name = name
        self.description = description
        self.logoUri = logoUri
        self.itemsCount = itemsCount
    }
}

/// Client for objkt.com GraphQL v3 API
public actor ObjktClient {
    public static let defaultEndpoint = URL(string: "https://data.objkt.com/v3/graphql")!

    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = defaultEndpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    /// Fetches all curations / galleries curated by a specific wallet address from objkt GraphQL
    public func fetchUserGalleries(curator: TezosAddress) async throws -> [ObjktGallerySummary] {
        let query = """
        query GetUserGalleries($curator: String!) {
          gallery(where: { curators: { curator_address: { _eq: $curator } } }, order_by: { items: desc }) {
            gallery_id
            slug
            name
            description
            logo
            items
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": ["curator": curator.raw]
        ]

        let data = try await executeGraphQL(payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let galleries = dataDict["gallery"] as? [[String: Any]] else {
            return []
        }

        return galleries.compactMap { dict in
            guard let gid = dict["gallery_id"] as? String ?? (dict["gallery_id"] as? NSNumber)?.stringValue,
                  let name = dict["name"] as? String else { return nil }

            let slug = (dict["slug"] as? String) ?? gid
            let desc = dict["description"] as? String
            let logo = dict["logo"] as? String
            let items = (dict["items"] as? NSNumber)?.intValue ?? 0

            return ObjktGallerySummary(
                galleryId: gid,
                slug: slug,
                name: name,
                description: desc,
                logoUri: logo,
                itemsCount: items
            )
        }
    }

    /// Fetches art tokens created / minted by a specific wallet from objkt GraphQL with pagination
    public func fetchCreatedTokens(creator: TezosAddress, limit: Int = 1000) async throws -> [UnifiedToken] {
        var allTokens: [UnifiedToken] = []
        var offset = 0
        let batchSize = 250

        while offset < limit {
            let query = """
            query GetCreatedTokens($creator: String!, $limit: Int!, $offset: Int!) {
              token(
                where: { creators: { creator_address: { _eq: $creator } } }
                limit: $limit
                offset: $offset
                order_by: { timestamp: desc }
              ) {
                fa_contract
                token_id
                name
                description
                mime
                artifact_uri
                display_uri
                thumbnail_uri
                supply
                decimals
                timestamp
                accessibility
                content_rating
                flag
                fa {
                  name
                  short_name
                }
                creators {
                  creator_address
                  holder {
                    address
                    alias
                  }
                }
                attributes {
                  attribute {
                    name
                    value
                  }
                }
              }
            }
            """

            let payload: [String: Any] = [
                "query": query,
                "variables": [
                    "creator": creator.raw,
                    "limit": batchSize,
                    "offset": offset
                ]
            ]

            let data = try await executeGraphQL(payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let tokens = dataDict["token"] as? [[String: Any]] else {
                break
            }

            let batch = tokens.compactMap { dict -> UnifiedToken? in
                parseObjktToken(from: dict)
            }

            allTokens.append(contentsOf: batch)

            if tokens.count < batchSize {
                break
            }
            offset += batchSize
        }

        return allTokens
    }

    /// Fetches tokens contained in an objkt.com curation / gallery
    /// Accepts either a curation slug (e.g. 8-char hex or full name) or a curation ID
    public func fetchCurationTokens(slugOrId: String, limit: Int = 100) async throws -> [UnifiedToken] {
        let query = """
        query GetGalleryTokens($slug: String!, $limit: Int!) {
          gallery(where: { _or: [{ slug: { _eq: $slug } }, { id: { _eq: $slug } }] }) {
            name
            tokens(limit: $limit) {
              token {
                fa_contract
                token_id
                name
                description
                mime
                artifact_uri
                display_uri
                thumbnail_uri
                supply
                decimals
                accessibility
                content_rating
                flag
                creators {
                  creator_address
                  holder {
                    address
                    alias
                  }
                }
                attributes {
                  attribute {
                    name
                    value
                  }
                }
              }
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": [
                "slug": slugOrId,
                "limit": limit
            ]
        ]

        let data = try await executeGraphQL(payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let galleries = dataDict["gallery"] as? [[String: Any]],
              let firstGallery = galleries.first,
              let galleryTokens = firstGallery["tokens"] as? [[String: Any]] else {
            return []
        }

        return galleryTokens.compactMap { item in
            guard let tokenDict = item["token"] as? [String: Any] else { return nil }
            return parseObjktToken(from: tokenDict)
        }
    }

    /// Fetches tokens for an entire contract collection via objkt.com GraphQL
    public func fetchCollectionTokens(contract: TezosAddress, limit: Int = 100, offset: Int = 0) async throws -> [UnifiedToken] {
        let query = """
        query GetCollectionTokens($contract: String!, $limit: Int!, $offset: Int!) {
          token(where: { fa_contract: { _eq: $contract } }, limit: $limit, offset: $offset, order_by: { token_id: asc }) {
            fa_contract
            token_id
            name
            description
            mime
            artifact_uri
            display_uri
            thumbnail_uri
            supply
            decimals
            accessibility
            content_rating
            flag
            creators {
              creator_address
              holder {
                address
                alias
              }
            }
            attributes {
              attribute {
                name
                value
              }
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": [
                "contract": contract.raw,
                "limit": limit,
                "offset": offset
            ]
        ]

        let data = try await executeGraphQL(payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let tokens = dataDict["token"] as? [[String: Any]] else {
            return []
        }

        return tokens.compactMap { parseObjktToken(from: $0) }
    }

    /// Fetches tokens for an fxhash generative token project by matching the project title pattern
    public func fetchFxhashProjectTokens(projectName: String, limit: Int = 200, offset: Int = 0) async throws -> [UnifiedToken] {
        let fxContracts = [
            "KT1KEa8z6vWXDJrVqtMrAeDVzsvxat3kHaCE",
            "KT1U6EHmNxJTkvaWJ4ThczG4FSDaHC21ssvi",
            "KT1U6EHmng3rqGzgWRjVm31tYmGwgyMo61gk",
            "KT1EfsNuqwLAWDd3o4pvfUx1CAh5GMdTrRvr",
            "KT1EfsNuqwLACdq3mAA3gkpjTrMmqqeS2nuv"
        ]
        let pattern = "\(projectName) #%"
        let query = """
        query GetFxhashProjectTokens($contracts: [String!]!, $pattern: String!, $limit: Int!, $offset: Int!) {
          token(
            where: { fa_contract: { _in: $contracts }, name: { _ilike: $pattern } },
            limit: $limit,
            offset: $offset,
            order_by: { token_id: asc }
          ) {
            fa_contract
            token_id
            name
            description
            mime
            artifact_uri
            display_uri
            thumbnail_uri
            supply
            decimals
            accessibility
            content_rating
            flag
            creators {
              creator_address
              holder {
                address
                alias
              }
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": [
                "contracts": fxContracts,
                "pattern": pattern,
                "limit": limit,
                "offset": offset
            ]
        ]

        let data = try await executeGraphQL(payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let tokens = dataDict["token"] as? [[String: Any]] else {
            return []
        }

        return tokens.compactMap { parseObjktToken(from: $0) }
    }

    /// Fetches all tokens in a collection or fxhash project (up to limit)
    public func fetchEntireCollection(key: String, limit: Int = 250) async throws -> [UnifiedToken] {
        if key.hasPrefix("fxhash:") {
            let projectName = String(key.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return try await fetchFxhashProjectTokens(projectName: projectName, limit: limit)
        } else {
            guard let address = TezosAddress(key) else { return [] }
            let tokens = try await fetchCollectionTokens(contract: address, limit: limit)
            if !tokens.isEmpty {
                return tokens
            }
            // Fallback to TzKT if objkt returned empty
            let tzkt = TzKTClient()
            return (try? await tzkt.fetchContractTokens(contract: address, limit: limit)) ?? []
        }
    }

    // MARK: - Private Helpers

    private func executeGraphQL(payload: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func parseObjktToken(from dict: [String: Any]) -> UnifiedToken? {
        guard let contract = dict["fa_contract"] as? String,
              let tokenId = dict["token_id"] as? String else {
            return nil
        }

        let name = dict["name"] as? String ?? "Token #\(tokenId)"
        let description = dict["description"] as? String
        let mime = dict["mime"] as? String
        let artifact = dict["artifact_uri"] as? String
        let display = dict["display_uri"] as? String
        let thumbnail = dict["thumbnail_uri"] as? String
        let supply = (dict["supply"] as? NSNumber)?.intValue
        let decimals = (dict["decimals"] as? NSNumber)?.intValue
        let contentRating = dict["content_rating"] as? String
        let moderationFlag = dict["flag"] as? String
        var hazards: [String] = []
        if let a11y = dict["accessibility"] as? [String: Any],
           let rawHazards = a11y["hazards"] as? [String] {
            hazards = rawHazards
        }

        // Creators
        var creators: [String] = []
        if let creatorsRaw = dict["creators"] as? [[String: Any]] {
            for c in creatorsRaw {
                if let addr = c["creator_address"] as? String, !addr.isEmpty, !creators.contains(addr) {
                    creators.append(addr)
                }
                if let holder = c["holder"] as? [String: Any] {
                    if let addr = holder["address"] as? String, !addr.isEmpty, !creators.contains(addr) {
                        creators.append(addr)
                    }
                    if let alias = holder["alias"] as? String, !alias.isEmpty, !creators.contains(alias) {
                        creators.append(alias)
                    }
                }
            }
        }

        // Attributes
        var attributes: [TokenAttribute] = []
        if let attributesRaw = dict["attributes"] as? [[String: Any]] {
            for a in attributesRaw {
                if let attr = a["attribute"] as? [String: Any],
                   let attrName = attr["name"] as? String {
                    let attrVal = "\(attr["value"] ?? "")"
                    attributes.append(TokenAttribute(name: attrName, value: attrVal))
                }
            }
        }

        var rawMeta: [String: String] = [:]
        if let timestamp = dict["timestamp"] as? String {
            rawMeta["timestamp"] = timestamp
            rawMeta["lastTime"] = timestamp
        }
        if let fa = dict["fa"] as? [String: Any], let faName = (fa["name"] as? String) ?? (fa["short_name"] as? String) {
            rawMeta["collectionName"] = faName
            rawMeta["contractAlias"] = faName
        }

        return UnifiedToken(
            contract: contract,
            tokenId: tokenId,
            name: name,
            description: description,
            creators: creators,
            mimeType: mime,
            artifactUri: artifact,
            displayUri: display,
            thumbnailUri: thumbnail,
            formats: [],
            attributes: attributes,
            supply: supply,
            decimals: decimals,
            aleatory: nil,
            rawMetadata: rawMeta.isEmpty ? nil : rawMeta,
            accessibilityHazards: hazards,
            contentRating: contentRating,
            moderationFlag: moderationFlag
        )
    }

    public struct SafetyMetadata: Sendable {
        public let hazards: [String]
        public let contentRating: String?
        public let flag: String?
    }

    /// Batch-fetches Objkt accessibility hazards, content_rating, and moderation flag for existing tokens.
    public func fetchSafetyMetadata(for tokens: [(contract: String, tokenId: String)]) async -> [String: SafetyMetadata] {
        var results: [String: SafetyMetadata] = [:]
        guard !tokens.isEmpty else { return results }

        let chunkSize = 100
        for start in stride(from: 0, to: tokens.count, by: chunkSize) {
            let chunk = Array(tokens[start..<min(start + chunkSize, tokens.count)])
            let orClauses: [[String: Any]] = chunk.map { item in
                [
                    "fa_contract": ["_eq": item.contract],
                    "token_id": ["_eq": item.tokenId]
                ]
            }
            let query = """
            query FetchSafetyFlags($where: token_bool_exp!, $limit: Int!) {
              token(where: $where, limit: $limit) {
                fa_contract
                token_id
                accessibility
                content_rating
                flag
                attributes(where: { attribute: { type: { _eq: "_objktcom" } } }) {
                  attribute {
                    name
                    value
                  }
                }
              }
            }
            """
            let payload: [String: Any] = [
                "query": query,
                "variables": [
                    "where": ["_or": orClauses],
                    "limit": chunk.count
                ]
            ]
            guard let data = try? await executeGraphQL(payload: payload),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let rows = dataObj["token"] as? [[String: Any]] else {
                continue
            }

            for row in rows {
                guard let c = row["fa_contract"] as? String,
                      let tid = row["token_id"] as? String else { continue }
                let key = "\(c):\(tid)"
                var hazards: [String] = []
                if let a11y = row["accessibility"] as? [String: Any],
                   let rawHazards = a11y["hazards"] as? [String] {
                    hazards = rawHazards
                }
                var rating = row["content_rating"] as? String
                if let attrs = row["attributes"] as? [[String: Any]] {
                    for a in attrs {
                        guard let attr = a["attribute"] as? [String: Any],
                              let attrName = attr["name"] as? String else { continue }
                        let attrVal = "\(attr["value"] ?? "")"
                        if attrName == "__hazards_" && attrVal.localizedCaseInsensitiveContains("flash") && !hazards.contains("flashing") {
                            hazards.append("flashing")
                        } else if attrName == "__nsfw_" && ["true", "1", "yes"].contains(attrVal.lowercased()) && rating == nil {
                            rating = "mature"
                        }
                    }
                }
                let flag = row["flag"] as? String
                results[key] = SafetyMetadata(hazards: hazards, contentRating: rating, flag: flag)
            }
        }
        return results
    }
}
