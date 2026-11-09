import Foundation

/// Network target for TzKT queries
public enum TezosNetwork: String, Sendable {
    case mainnet = "https://api.tzkt.io"
    case shadownet = "https://api.shadownet.tzkt.io"
    case ghostnet = "https://api.ghostnet.tzkt.io"

    public var baseURL: URL {
        URL(string: rawValue)!
    }
}

/// Client for fetching token balances, metadata, and contract tokens via TzKT REST API
public actor TzKTClient {
    private let session: URLSession
    private let network: TezosNetwork

    public init(session: URLSession = .shared, network: TezosNetwork = .mainnet) {
        self.session = session
        self.network = network
    }

    /// Fetches all tokens held by a specific wallet address across all paginated batches
    public func fetchAllTokens(
        for address: TezosAddress,
        pageSize: Int = 500,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> [UnifiedToken] {
        var allTokens: [UnifiedToken] = []
        var offset = 0

        while true {
            var components = URLComponents(url: network.baseURL.appendingPathComponent("v1/tokens/balances"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "account", value: address.raw),
                URLQueryItem(name: "balance.gt", value: "0"),
                URLQueryItem(name: "token.metadata.null", value: "false"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset))
            ]

            guard let url = components.url else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 429 {
                // Rate limited by TzKT - wait 1 second and retry
                try await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let balances = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                break
            }

            if balances.isEmpty {
                break
            }

            let pageTokens = balances.compactMap { balanceDict -> UnifiedToken? in
                guard let tokenDict = balanceDict["token"] as? [String: Any],
                      let parsed = parseUnifiedToken(from: tokenDict) else { return nil }
                var meta = parsed.rawMetadata ?? [:]
                if let lastTime = balanceDict["lastTime"] as? String {
                    meta["lastTime"] = lastTime
                }
                if let firstTime = balanceDict["firstTime"] as? String {
                    meta["firstTime"] = firstTime
                }
                return UnifiedToken(
                    contract: parsed.contract,
                    tokenId: parsed.tokenId,
                    name: parsed.name,
                    description: parsed.description,
                    creators: parsed.creators,
                    mimeType: parsed.mimeType,
                    artifactUri: parsed.artifactUri,
                    displayUri: parsed.displayUri,
                    thumbnailUri: parsed.thumbnailUri,
                    formats: parsed.formats,
                    attributes: parsed.attributes,
                    supply: parsed.supply,
                    decimals: parsed.decimals,
                    aleatory: parsed.aleatory,
                    rawMetadata: meta,
                    isOwned: true,
                    isCreated: parsed.isCreated
                )
            }

            allTokens.append(contentsOf: pageTokens)
            onProgress?(allTokens.count)

            if balances.count < pageSize {
                break
            }

            offset += balances.count
            // Small pause between batches to prevent 429
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return allTokens
    }

    /// Fetches all tokens held by a specific wallet address
    public func fetchTokens(for address: TezosAddress, limit: Int = 100, offset: Int = 0) async throws -> [UnifiedToken] {
        var components = URLComponents(url: network.baseURL.appendingPathComponent("v1/tokens/balances"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "account", value: address.raw),
            URLQueryItem(name: "balance.gt", value: "0"),
            URLQueryItem(name: "token.metadata.null", value: "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let balances = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return balances.compactMap { balanceDict in
            guard let tokenDict = balanceDict["token"] as? [String: Any] else { return nil }
            return parseUnifiedToken(from: tokenDict)
        }
    }

    /// Fetches tokens minted under a specific contract (e.g. fxhash, HEN, or Aleatory generator)
    public func fetchContractTokens(contract: TezosAddress, limit: Int = 100, offset: Int = 0) async throws -> [UnifiedToken] {
        var components = URLComponents(url: network.baseURL.appendingPathComponent("v1/tokens"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "contract", value: contract.raw),
            URLQueryItem(name: "metadata.null", value: "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let tokensList = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return tokensList.compactMap { tokenDict in
            return parseUnifiedToken(from: tokenDict)
        }
    }

    // MARK: - Parsing

    private func parseUnifiedToken(from dict: [String: Any]) -> UnifiedToken? {
        guard let contractDict = dict["contract"] as? [String: Any],
              let contractAddress = contractDict["address"] as? String,
              let tokenId = dict["tokenId"] as? String else {
            return nil
        }

        let metadata = dict["metadata"] as? [String: Any] ?? [:]
        let name = metadata["name"] as? String ?? "Token #\(tokenId)"
        let description = metadata["description"] as? String

        // Creators extraction: support array of strings, array of dicts, single string, or creator/author keys
        var creators: [String] = []
        if let creatorsArray = metadata["creators"] as? [String] {
            creators = creatorsArray
        } else if let creatorsAnyArray = metadata["creators"] as? [Any] {
            for item in creatorsAnyArray {
                if let str = item as? String {
                    creators.append(str)
                } else if let dict = item as? [String: Any] {
                    if let addr = (dict["address"] as? String) ?? (dict["creator"] as? String) ?? (dict["holder"] as? String) {
                        creators.append(addr)
                    } else if let name = dict["name"] as? String {
                        creators.append(name)
                    }
                }
            }
        } else if let creatorString = metadata["creators"] as? String {
            creators = [creatorString]
        } else if let singleCreator = metadata["creator"] as? String {
            creators = [singleCreator]
        } else if let authors = metadata["authors"] as? [String] {
            creators = authors
        } else if let tags = metadata["tags"] as? [String] {
            creators = tags.filter { $0.hasPrefix("creator:") }
        }

        // Check if root token object has creator
        if creators.isEmpty, let rootCreator = dict["creator"] as? [String: Any], let addr = rootCreator["address"] as? String {
            creators = [addr]
        }

        let artifactUri = metadata["artifactUri"] as? String
        let displayUri = metadata["displayUri"] as? String
        let thumbnailUri = metadata["thumbnailUri"] as? String

        // Formats extraction
        var formats: [TokenFormat] = []
        if let formatsRaw = metadata["formats"] as? [[String: Any]] {
            for f in formatsRaw {
                let uri = f["uri"] as? String
                let mime = f["mimeType"] as? String
                let dimensions = f["dimensions"] as? [String: Any]
                let dimString: String? = dimensions.flatMap { d in
                    if let val = d["value"] as? String { return val }
                    if let w = d["width"], let h = d["height"] { return "\(w)x\(h)" }
                    return nil
                }
                let fileSize = (f["fileSize"] as? NSNumber)?.int64Value
                let hash = f["hash"] as? String
                formats.append(TokenFormat(uri: uri, mimeType: mime, dimensions: dimString, fileSize: fileSize, hash: hash))
            }
        }

        // Attributes extraction
        var attributes: [TokenAttribute] = []
        if let attributesRaw = metadata["attributes"] as? [[String: Any]] {
            for a in attributesRaw {
                if let attrName = a["name"] as? String {
                    let attrVal = "\(a["value"] ?? "")"
                    attributes.append(TokenAttribute(name: attrName, value: attrVal))
                }
            }
        }

        // Supply and decimals
        let supplyInt: Int? = {
            if let ts = dict["totalSupply"] as? String { return Int(ts) }
            if let tsNum = dict["totalSupply"] as? NSNumber { return tsNum.intValue }
            return nil
        }()

        let decimalsInt: Int? = {
            if let dec = metadata["decimals"] as? String { return Int(dec) }
            if let decNum = metadata["decimals"] as? NSNumber { return decNum.intValue }
            if let decDirect = dict["decimals"] as? String { return Int(decDirect) }
            if let decDirectNum = dict["decimals"] as? NSNumber { return decDirectNum.intValue }
            return nil
        }()

        // Aleatory metadata extraction
        var aleatoryMeta: AleatoryMetadata? = nil
        if let aleaDict = metadata["aleatory"] as? [String: Any] {
            aleatoryMeta = AleatoryMetadata(
                code: aleaDict["code"] as? String,
                seed: aleaDict["seed"] as? String,
                params: aleaDict["params"] as? String,
                provider: aleaDict["provider"] as? String,
                encoding: aleaDict["encoding"] as? String,
                version: (aleaDict["version"] as? NSNumber)?.intValue
            )
        }

        // Flatten metadata for raw access
        var rawMeta: [String: String] = [:]
        for (k, v) in metadata {
            if let str = v as? String {
                rawMeta[k] = str
            }
        }
        if let tagsArray = metadata["tags"] as? [String] {
            rawMeta["tags"] = tagsArray.joined(separator: ",")
        }
        if let contractAlias = contractDict["alias"] as? String, !contractAlias.isEmpty {
            rawMeta["contractAlias"] = contractAlias
        }

        // Resolve the true artifact MIME type (prioritizing the master artifact over generated display/thumbnail WebP/JPEG)
        let artifactFormat = formats.first(where: {
            guard let fUri = $0.uri, let aUri = artifactUri else { return false }
            return fUri == aUri || fUri.contains(aUri) || aUri.contains(fUri)
        })
        let gifFormat = formats.first(where: { ($0.mimeType ?? "").lowercased() == "image/gif" })
        let videoFormat = formats.first(where: { ($0.mimeType ?? "").lowercased().hasPrefix("video/") })
        let htmlFormat = formats.first(where: {
            let m = ($0.mimeType ?? "").lowercased()
            return m == "text/html" || m == "application/x-directory"
        })
        let hasGifTag = (rawMeta["tags"] ?? "").lowercased().contains("gif")

        let mimeType: String? = {
            if let m = artifactFormat?.mimeType, !m.isEmpty { return m }
            if let m = metadata["mimeType"] as? String, !m.isEmpty { return m }
            if let m = gifFormat?.mimeType { return m }
            if hasGifTag { return "image/gif" }
            if let m = videoFormat?.mimeType { return m }
            if let m = htmlFormat?.mimeType { return m }
            return formats.first?.mimeType
        }()

        return UnifiedToken(
            contract: contractAddress,
            tokenId: tokenId,
            name: name,
            description: description,
            creators: creators,
            mimeType: mimeType,
            artifactUri: artifactUri,
            displayUri: displayUri,
            thumbnailUri: thumbnailUri,
            formats: formats,
            attributes: attributes,
            supply: supplyInt,
            decimals: decimalsInt,
            aleatory: aleatoryMeta,
            rawMetadata: rawMeta
        )
    }
}
