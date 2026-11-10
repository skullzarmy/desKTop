import Foundation
import desKTopCore

@main
struct desKTopCLI {
    static func main() async {
        print("=== desKTop v1.0 CLI ===")
        print("a FAFOlab joint - https://fafolab.xyz\n")

        let args = CommandLine.arguments.dropFirst()
        let query = args.first ?? "builder.hack"

        print("Testing query: '\(query)'")

        // 1. Check if it's a domain or address
        if let domain = TezosDomain(query) {
            print("[OK] Detected Tezos Domain: \(domain.name)")
            print("  Normalized: \(domain.normalized)")
            print("  isHackSubdomain: \(domain.isHackSubdomain)")

            print("Resolving domain via TezosDomainsResolver...")
            let resolver = TezosDomainsResolver()
            do {
                if let profile = try await resolver.resolve(domainInput: domain.normalized) {
                    print("[OK] Resolved address: \(profile.address)")
                    if let avatar = profile.avatarUri {
                        print("  Avatar URI: \(avatar)")
                    }
                    if let twitter = profile.twitter {
                        print("  Twitter: \(twitter)")
                    }
                } else {
                    print("  Domain resolution returned nil (not registered or offline).")
                }
            } catch {
                print("  Resolution error: \(error.localizedDescription)")
            }
        } else if let address = TezosAddress(query) {
            print("[OK] Validated Tezos Address: \(address.raw) (type: \(address.type))")

            print("Fetching recent tokens via TzKT...")
            let tzkt = TzKTClient()
            let filter = FungibleFilterEngine()

            do {
                let tokens = try await tzkt.fetchTokens(for: address, limit: 10)
                print("  Found \(tokens.count) raw tokens from TzKT.")

                let filtered = filter.filter(tokens)
                print("  [OK] Passed art filter: \(filtered.count) tokens.")

                for token in filtered.prefix(3) {
                    print("    - [\(token.id)] \(token.name) (Category: \(token.mediaCategory))")
                    if let uri = token.primaryWallpaperUri {
                        print("      Wallpaper URI: \(uri)")
                    }
                }
            } catch {
                print("  TzKT query failed: \(error.localizedDescription)")
            }
        } else {
            print("[ERROR] Input is neither a valid Tezos address nor a supported Tezos domain format.")
        }
    }
}
