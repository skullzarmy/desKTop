import Foundation

/// Client for objkt.com GraphQL v3 API
public actor ObjktClient {
    public static let defaultEndpoint = URL(string: "https://data.objkt.com/v3/graphql")!

    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = defaultEndpoint) {
        self.session = session
        self.endpoint = endpoint
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
                creators {
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
            creators {
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

        // Creators
        var creators: [String] = []
        if let creatorsRaw = dict["creators"] as? [[String: Any]] {
            for c in creatorsRaw {
                if let holder = c["holder"] as? [String: Any] {
                    if let alias = holder["alias"] as? String, !alias.isEmpty {
                        creators.append(alias)
                    } else if let addr = holder["address"] as? String {
                        creators.append(addr)
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
            rawMetadata: nil
        )
    }
}
