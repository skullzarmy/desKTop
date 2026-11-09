import Foundation

/// Circuit breaker status for a specific gateway endpoint
public struct GatewayStatus: Sendable {
    public var failureCount: Int = 0
    public var quarantinedUntil: Date?

    public var isAvailable: Bool {
        guard let quarantinedUntil = quarantinedUntil else { return true }
        return Date() >= quarantinedUntil
    }
}

/// Actor managing IPFS & Arweave gateway endpoints with circuit-breaker quarantines and fallback racing
public actor IPFSGatewayManager {
    public static let defaultIPFSGateways: [URL] = [
        URL(string: "https://ipfs.io/ipfs/")!,
        URL(string: "https://dweb.link/ipfs/")!,
        URL(string: "https://gateway.pinata.cloud/ipfs/")!,
        URL(string: "https://cloudflare-ipfs.com/ipfs/")!
    ]

    public static let defaultArweaveGateways: [URL] = [
        URL(string: "https://arweave.net/")!,
        URL(string: "https://arweave.dev/")!
    ]

    public static let quarantineDuration: TimeInterval = 15 * 60 // 15 minutes

    private let ipfsGateways: [URL]
    private let arweaveGateways: [URL]
    private var gatewayHealth: [URL: GatewayStatus] = [:]
    private let session: URLSession

    public init(
        ipfsGateways: [URL] = defaultIPFSGateways,
        arweaveGateways: [URL] = defaultArweaveGateways,
        session: URLSession = .shared
    ) {
        self.ipfsGateways = ipfsGateways
        self.arweaveGateways = arweaveGateways
        self.session = session

        for g in ipfsGateways + arweaveGateways {
            self.gatewayHealth[g] = GatewayStatus()
        }
    }

    /// Resolves any decentralized URI (ipfs:// or ar://) or raw CID to candidate HTTP gateway URLs in order of preference
    public func resolveCandidateURLs(for uriString: String) -> [URL] {
        let trimmed = uriString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. HTTP/HTTPS pass-through
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let url = URL(string: trimmed) {
                return [url]
            }
            return []
        }

        // 2. Arweave uri: ar://<tx_id>
        if trimmed.hasPrefix("ar://") {
            let txId = String(trimmed.dropFirst(5))
            return activeGateways(for: arweaveGateways).compactMap { gateway in
                URL(string: txId, relativeTo: gateway)?.absoluteURL
            }
        }

        // 3. IPFS uri: ipfs://<cid>[/path] or raw CID
        var ipfsPath = trimmed
        if ipfsPath.hasPrefix("ipfs://") {
            ipfsPath = String(ipfsPath.dropFirst(7))
        }

        // Strip leading "ipfs/" if present
        if ipfsPath.hasPrefix("ipfs/") {
            ipfsPath = String(ipfsPath.dropFirst(5))
        }

        return activeGateways(for: ipfsGateways).compactMap { gateway in
            URL(string: ipfsPath, relativeTo: gateway)?.absoluteURL
        }
    }

    /// Fetches data with automatic fallback racing across healthy gateways
    public func fetchData(from uriString: String, timeoutPerGateway: TimeInterval = 10.0) async throws -> (Data, URL) {
        let candidates = resolveCandidateURLs(for: uriString)
        guard !candidates.isEmpty else {
            throw URLError(.badURL)
        }

        var lastError: Error = URLError(.cannotConnectToHost)

        for candidateURL in candidates {
            guard let gatewayBase = extractGatewayBase(for: candidateURL) else { continue }

            do {
                var request = URLRequest(url: candidateURL)
                request.timeoutInterval = timeoutPerGateway
                request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 429 || httpResponse.statusCode == 504 || httpResponse.statusCode >= 500 {
                        recordFailure(for: gatewayBase, status: httpResponse.statusCode)
                        continue
                    }
                    if (200...299).contains(httpResponse.statusCode) {
                        recordSuccess(for: gatewayBase)
                        return (data, candidateURL)
                    }
                }
            } catch {
                recordFailure(for: gatewayBase, status: 0)
                lastError = error
                continue
            }
        }

        throw lastError
    }

    // MARK: - Health & Circuit Breaker Tracking

    private func activeGateways(for list: [URL]) -> [URL] {
        return list.filter { gateway in
            gatewayHealth[gateway]?.isAvailable ?? true
        }
    }

    private func extractGatewayBase(for url: URL) -> URL? {
        for g in ipfsGateways + arweaveGateways {
            if url.absoluteString.hasPrefix(g.absoluteString) {
                return g
            }
        }
        return nil
    }

    private func recordSuccess(for gateway: URL) {
        gatewayHealth[gateway] = GatewayStatus(failureCount: 0, quarantinedUntil: nil)
    }

    private func recordFailure(for gateway: URL, status: Int) {
        var current = gatewayHealth[gateway] ?? GatewayStatus()
        current.failureCount += 1

        // Immediate quarantine on 429 Too Many Requests or 3+ failures
        if status == 429 || status == 504 || current.failureCount >= 3 {
            current.quarantinedUntil = Date().addingTimeInterval(Self.quarantineDuration)
        }
        gatewayHealth[gateway] = current
    }

    public func isGatewayQuarantined(_ gateway: URL) -> Bool {
        return !(gatewayHealth[gateway]?.isAvailable ?? true)
    }
}
