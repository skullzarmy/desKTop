import Foundation

print("=== Running desKTop Unit Test Suite ===")

var totalPassed = 0
var totalFailed = 0

@MainActor
func runSuite(name: String, block: () async throws -> Void) async {
    print("\n[TEST SUITE] \(name)...", terminator: " ")
    do {
        try await block()
        print("✓ PASSED")
        totalPassed += 1
    } catch let failure as TestFailure {
        print("❌ FAILED: \(failure.message) at \(failure.file):\(failure.line)")
        totalFailed += 1
    } catch {
        print("❌ FAILED: \(error)")
        totalFailed += 1
    }
}

// Phase 1 Tests
await runSuite(name: "TezosAddressTests") {
    try TezosAddressTests.run()
}

await runSuite(name: "TezosDomainTests") {
    try TezosDomainTests.run()
}

await runSuite(name: "FungibleFilterTests") {
    try FungibleFilterTests.run()
}

await runSuite(name: "UnifiedTokenTests") {
    try UnifiedTokenTests.run()
}

await runSuite(name: "WalletRepositoryTests") {
    try await WalletRepositoryTests.run()
}

// Phase 2 Tests
await runSuite(name: "IPFSGatewayManagerTests") {
    try await IPFSGatewayManagerTests.run()
}

await runSuite(name: "MediaTypeDetectorTests") {
    try MediaTypeDetectorTests.run()
}

await runSuite(name: "MediaVaultTests") {
    try await MediaVaultTests.run()
}

// Phase 3 Tests
await runSuite(name: "DesktopEngineTests") {
    try await DesktopEngineTests.run()
}

print("\n==========================================")
print("Results: \(totalPassed) passed, \(totalFailed) failed.")
print("==========================================")

if totalFailed > 0 {
    exit(1)
}
