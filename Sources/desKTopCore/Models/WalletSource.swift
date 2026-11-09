import Foundation

/// Type of source for token ingestion
public enum SourceType: Hashable, Codable, Sendable {
    case wallet(address: TezosAddress, domain: TezosDomain?)
    case collection(contract: TezosAddress, name: String?)
    case objktCuration(curationId: String, name: String?)
}

/// Represents an active source configured by the user
public struct WalletSource: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var type: SourceType
    public var displayName: String
    public var avatarUri: String?
    public var isEnabled: Bool
    public let dateAdded: Date
    public var lastSynced: Date?
    public var tokenCount: Int

    public init(
        id: UUID = UUID(),
        type: SourceType,
        displayName: String,
        avatarUri: String? = nil,
        isEnabled: Bool = true,
        dateAdded: Date = Date(),
        lastSynced: Date? = nil,
        tokenCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.avatarUri = avatarUri
        self.isEnabled = isEnabled
        self.dateAdded = dateAdded
        self.lastSynced = lastSynced
        self.tokenCount = tokenCount
    }

    /// Convenience accessor for wallet address if source is a wallet
    public var walletAddress: String? {
        if case .wallet(let addr, _) = type {
            return addr.raw
        }
        return nil
    }

    /// Convenience factory for wallet addresses
    public static func fromAddress(_ address: TezosAddress, domain: TezosDomain? = nil, label: String? = nil) -> WalletSource {
        let name = label ?? domain?.normalized ?? address.raw
        return WalletSource(
            type: .wallet(address: address, domain: domain),
            displayName: name
        )
    }

    /// Convenience factory for collection contracts
    public static func fromCollection(contract: TezosAddress, name: String? = nil) -> WalletSource {
        return WalletSource(
            type: .collection(contract: contract, name: name),
            displayName: name ?? contract.raw
        )
    }

    /// Convenience factory for objkt curations
    public static func fromObjktCuration(curationId: String, name: String? = nil) -> WalletSource {
        return WalletSource(
            type: .objktCuration(curationId: curationId, name: name),
            displayName: name ?? "Curation \(curationId)"
        )
    }
}
