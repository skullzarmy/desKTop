import Foundation

/// Tezos Domains model supporting 2LDs (name.tez), subdomains (*.domain.tez),
/// and smart shorthands (*.hack -> *.hack.tez)
public struct TezosDomain: Hashable, Codable, CustomStringConvertible, Sendable {
    public let name: String
    public let normalized: String

    public var description: String { normalized }

    public init?(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Expand smart shorthand: e.g. "builder.hack" -> "builder.hack.tez"
        var candidate = trimmed
        if candidate.hasSuffix(".hack") {
            candidate += ".tez"
        }

        // Reject consecutive dots
        guard !candidate.contains("..") else { return nil }

        // Must end with .tez
        guard candidate.hasSuffix(".tez") else { return nil }

        // Validate domain labels
        let labels = candidate.split(separator: ".")
        guard labels.count >= 2 else { return nil }

        // Each label must be alphanumeric or hyphen, cannot start/end with hyphen
        let validLabel = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for label in labels {
            guard !label.isEmpty else { return nil }
            guard label.rangeOfCharacter(from: validLabel.inverted) == nil else { return nil }
            guard !label.hasPrefix("-") && !label.hasSuffix("-") else { return nil }
        }

        self.name = trimmed
        self.normalized = candidate
    }

    /// Whether this domain is a hack.tez subdomain
    public var isHackSubdomain: Bool {
        normalized.hasSuffix(".hack.tez")
    }
}
