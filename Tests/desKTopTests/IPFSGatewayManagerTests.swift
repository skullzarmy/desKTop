import Foundation
import desKTopCore

public struct IPFSGatewayManagerTests {
    public static func run() async throws {
        let manager = IPFSGatewayManager()

        // 1. IPFS candidate resolution
        let ipfsURI = "ipfs://QmZtmD2qtMeBP6a8Jmxqc18dge4gn8CmQU4ja659rB3qmK"
        let ipfsCandidates = await manager.resolveCandidateURLs(for: ipfsURI)
        try assertTrue(!ipfsCandidates.isEmpty, "IPFS candidates should not be empty")
        try assertTrue(ipfsCandidates.first?.absoluteString.contains("QmZtmD2qtMeBP6a8Jmxqc18dge4gn8CmQU4ja659rB3qmK") ?? false)

        // 2. Arweave candidate resolution
        let arURI = "ar://a1b2c3d4e5"
        let arCandidates = await manager.resolveCandidateURLs(for: arURI)
        try assertTrue(!arCandidates.isEmpty, "Arweave candidates should not be empty")
        try assertTrue(arCandidates.first?.absoluteString.contains("a1b2c3d4e5") ?? false)

        // 3. HTTP Pass-through
        let httpURI = "https://example.com/art.png"
        let httpCandidates = await manager.resolveCandidateURLs(for: httpURI)
        try assertEqual(httpCandidates.count, 1)
        try assertEqual(httpCandidates.first?.absoluteString, httpURI)
    }
}
