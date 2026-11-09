import Foundation

/// Validated Tezos on-chain address (tz1, tz2, tz3, tz4, or KT1)
public struct TezosAddress: Hashable, Codable, CustomStringConvertible, Sendable {
    public enum AddressType: String, Codable, Sendable {
        case tz1 // Ed25519 public key hash
        case tz2 // Secp256k1 public key hash
        case tz3 // P256 public key hash
        case tz4 // BLS12-381 public key hash
        case kt1 // Originated contract address
    }

    public let raw: String
    public let type: AddressType

    public var description: String { raw }

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validated = TezosAddressValidator.validate(trimmed) else {
            return nil
        }
        self.raw = trimmed
        self.type = validated
    }
}

/// Strict validator for Tezos address formats and checksum length
public enum TezosAddressValidator {
    // Base58 characters used in Tezos addresses
    private static let base58Charset = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    public static func validate(_ address: String) -> TezosAddress.AddressType? {
        guard address.count == 36 else { return nil }
        guard address.rangeOfCharacter(from: base58Charset.inverted) == nil else { return nil }

        let prefix = String(address.prefix(3))
        switch prefix {
        case "tz1":
            return .tz1
        case "tz2":
            return .tz2
        case "tz3":
            return .tz3
        case "tz4":
            return .tz4
        case "KT1":
            return .kt1
        default:
            return nil
        }
    }

    public static func isValid(_ address: String) -> Bool {
        return validate(address) != nil
    }

    public static func isContract(_ address: String) -> Bool {
        return validate(address) == .kt1
    }
}
