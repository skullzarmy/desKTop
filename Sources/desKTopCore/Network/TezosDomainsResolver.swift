import Foundation

/// Resolved domain profile information
public struct DomainProfile: Hashable, Codable, Sendable {
    public let domain: String
    public let address: String
    public let avatarUri: String?
    public let twitter: String?
    public let github: String?
    public let website: String?
    public let data: [String: String]

    public init(
        domain: String,
        address: String,
        avatarUri: String? = nil,
        twitter: String? = nil,
        github: String? = nil,
        website: String? = nil,
        data: [String: String] = [:]
    ) {
        self.domain = domain
        self.address = address
        self.avatarUri = avatarUri
        self.twitter = twitter
        self.github = github
        self.website = website
        self.data = data
    }
}

/// Resolver for Tezos Domains with GraphQL API, TzKT fallback, and official hack.tez API support
public actor TezosDomainsResolver {
    public static let defaultGraphQLEndpoint = URL(string: "https://api.tezos.domains/graphql")!
    public static let defaultTzKTEndpoint = URL(string: "https://api.tzkt.io/v1/domains")!
    public static let defaultHackTezEndpoint = URL(string: "https://hacktez.com/api/v1")!

    private let session: URLSession
    private let graphqlEndpoint: URL
    private let tzktEndpoint: URL
    private let hacktezEndpoint: URL

    public init(
        session: URLSession = .shared,
        graphqlEndpoint: URL = defaultGraphQLEndpoint,
        tzktEndpoint: URL = defaultTzKTEndpoint,
        hacktezEndpoint: URL = defaultHackTezEndpoint
    ) {
        self.session = session
        self.graphqlEndpoint = graphqlEndpoint
        self.tzktEndpoint = tzktEndpoint
        self.hacktezEndpoint = hacktezEndpoint
    }

    /// Forward resolution: Resolves a domain or smart shorthand (e.g. "skllz.hack" -> "skllz.hack.tez") to an address and profile
    public func resolve(domainInput: String) async throws -> DomainProfile? {
        guard let domain = TezosDomain(domainInput) else {
            return nil
        }

        // If it's a *.hack or *.hack.tez domain, query official hack.tez API directly
        if domain.isHackSubdomain {
            if let profile = try await resolveViaHackTez(domain: domain.normalized) {
                return profile
            }
        }

        // Try primary GraphQL endpoint first
        do {
            if let profile = try await resolveViaGraphQL(domain: domain.normalized) {
                return profile
            }
        } catch {
            // Fall back to TzKT domains API
        }

        // TzKT fallback
        if let profile = try await resolveViaTzKT(domain: domain.normalized) {
            return profile
        }

        // Fallback to hack.tez resolver in case domain wasn't marked hack subdomain
        return try await resolveViaHackTez(domain: domain.normalized)
    }

    /// Reverse resolution: Resolves a Tezos address to primary domain and profile
    public func reverseResolve(address: TezosAddress) async throws -> DomainProfile? {
        do {
            if let profile = try await reverseViaGraphQL(address: address.raw) {
                return profile
            }
        } catch {
            // Fall back
        }

        do {
            if let profile = try await reverseViaHackTez(address: address.raw) {
                return profile
            }
        } catch {
            // Fall back
        }

        return try await reverseViaTzKT(address: address.raw)
    }

    // MARK: - Private Implementations

    private func resolveViaGraphQL(domain: String) async throws -> DomainProfile? {
        let query = """
        query ResolveDomain($name: String!) {
          domain(name: $name) {
            name
            address
            data {
              key
              value
            }
          }
        }
        """

        var request = URLRequest(url: graphqlEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "query": query,
            "variables": ["name": domain]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let domainDict = dataDict["domain"] as? [String: Any],
              let address = domainDict["address"] as? String else {
            return nil
        }

        var records: [String: String] = [:]
        if let dataItems = domainDict["data"] as? [[String: Any]] {
            for item in dataItems {
                if let key = item["key"] as? String, let val = item["value"] as? String {
                    records[key] = val
                }
            }
        }

        return DomainProfile(
            domain: domain,
            address: address,
            avatarUri: records["avatar"] ?? records["gravatar"],
            twitter: records["twitter"],
            github: records["github"],
            website: records["website"],
            data: records
        )
    }

    private func reverseViaGraphQL(address: String) async throws -> DomainProfile? {
        let query = """
        query ReverseResolve($address: String!) {
          reverseRecord(address: $address) {
            domain {
              name
              address
              data {
                key
                value
              }
            }
          }
        }
        """

        var request = URLRequest(url: graphqlEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "query": query,
            "variables": ["address": address]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let reverseRecord = dataDict["reverseRecord"] as? [String: Any],
              let domainDict = reverseRecord["domain"] as? [String: Any],
              let domainName = domainDict["name"] as? String else {
            return nil
        }

        var records: [String: String] = [:]
        if let dataItems = domainDict["data"] as? [[String: Any]] {
            for item in dataItems {
                if let key = item["key"] as? String, let val = item["value"] as? String {
                    records[key] = val
                }
            }
        }

        return DomainProfile(
            domain: domainName,
            address: address,
            avatarUri: records["avatar"] ?? records["gravatar"],
            twitter: records["twitter"],
            github: records["github"],
            website: records["website"],
            data: records
        )
    }

    private func resolveViaTzKT(domain: String) async throws -> DomainProfile? {
        guard var components = URLComponents(url: tzktEndpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "name", value: domain)]

        guard let url = components.url else { return nil }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = list.first,
              let address = first["address"] as? String else {
            return nil
        }

        var records: [String: String] = [:]
        if let dataDict = first["data"] as? [String: Any] {
            for (k, v) in dataDict {
                if let stringVal = v as? String {
                    records[k] = stringVal
                }
            }
        }

        return DomainProfile(
            domain: domain,
            address: address,
            avatarUri: records["avatar"],
            twitter: records["twitter"],
            github: records["github"],
            website: records["website"],
            data: records
        )
    }

    private func reverseViaTzKT(address: String) async throws -> DomainProfile? {
        guard var components = URLComponents(url: tzktEndpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "reverse", value: "true")
        ]

        guard let url = components.url else { return nil }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = list.first,
              let domainName = first["name"] as? String else {
            return nil
        }

        return DomainProfile(
            domain: domainName,
            address: address
        )
    }

    private func resolveViaHackTez(domain: String) async throws -> DomainProfile? {
        let cleanName = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        // HackTez member endpoint accepts bare label or full domain name
        let memberURL = hacktezEndpoint.appendingPathComponent("members").appendingPathComponent(cleanName)
        var request = URLRequest(url: memberURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let memberData = json["data"] as? [String: Any] else {
            return nil
        }

        // When address is null, owner is the authoritative wallet address
        guard let resolvedAddress = (memberData["address"] as? String) ?? (memberData["owner"] as? String),
              !resolvedAddress.isEmpty else {
            return nil
        }

        let name = (memberData["name"] as? String) ?? cleanName
        let urls = memberData["urls"] as? [String: Any]
        let profile = memberData["profile"] as? [String: Any]

        let avatarUri = (profile?["picture"] as? String) ?? (urls?["avatar"] as? String)
        let twitter = profile?["twitter"] as? String
        let github = profile?["github"] as? String
        let website = profile?["website"] as? String

        var records: [String: String] = [:]
        if let profile = profile {
            for (k, v) in profile {
                if let str = v as? String {
                    records[k] = str
                }
            }
        }

        return DomainProfile(
            domain: name,
            address: resolvedAddress,
            avatarUri: avatarUri,
            twitter: twitter,
            github: github,
            website: website,
            data: records
        )
    }

    private func reverseViaHackTez(address: String) async throws -> DomainProfile? {
        var components = URLComponents(url: hacktezEndpoint.appendingPathComponent("hackers"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "owner", value: address)]

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]],
              let first = list.first else {
            return nil
        }

        let hacker = first["hacker"] as? [String: Any]
        let primaryDomain = (hacker?["primary"] as? String) ?? (first["name"] as? String)
        guard let domain = primaryDomain, !domain.isEmpty else { return nil }

        let resolvedAddress = (first["address"] as? String) ?? (first["owner"] as? String) ?? address
        let urls = first["urls"] as? [String: Any]
        let profile = first["profile"] as? [String: Any]

        let avatarUri = (profile?["picture"] as? String) ?? (urls?["avatar"] as? String)
        let twitter = profile?["twitter"] as? String
        let github = profile?["github"] as? String
        let website = profile?["website"] as? String

        var records: [String: String] = [:]
        if let profile = profile {
            for (k, v) in profile {
                if let str = v as? String {
                    records[k] = str
                }
            }
        }

        return DomainProfile(
            domain: domain,
            address: resolvedAddress,
            avatarUri: avatarUri,
            twitter: twitter,
            github: github,
            website: website,
            data: records
        )
    }
}
