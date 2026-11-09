import Foundation
import desKTopCore

public struct TezosDomainTests {
    public static func run() throws {
        // Standard domain
        let domain = TezosDomain("alice.tez")
        try assertNotNil(domain)
        try assertEqual(domain?.normalized, "alice.tez")
        try assertFalse(domain?.isHackSubdomain ?? true)

        // Subdomain
        let sub = TezosDomain("art.alice.tez")
        try assertNotNil(sub)
        try assertEqual(sub?.normalized, "art.alice.tez")

        // Smart shorthand builder.hack -> builder.hack.tez
        let shorthand = TezosDomain("builder.hack")
        try assertNotNil(shorthand)
        try assertEqual(shorthand?.normalized, "builder.hack.tez")
        try assertTrue(shorthand?.isHackSubdomain ?? false)

        let full = TezosDomain("vitalik.hack.tez")
        try assertNotNil(full)
        try assertEqual(full?.normalized, "vitalik.hack.tez")
        try assertTrue(full?.isHackSubdomain ?? false)

        // Invalids
        try assertNil(TezosDomain("invalid"))
        try assertNil(TezosDomain(".tez"))
        try assertNil(TezosDomain("alice..tez"))
        try assertNil(TezosDomain("-alice.tez"))
        try assertNil(TezosDomain("alice-.tez"))
        try assertNil(TezosDomain("alice!@#.tez"))
    }
}
