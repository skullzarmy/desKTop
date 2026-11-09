import Foundation

/// User-defined desktop wallpaper gallery / playlist
public struct DesktopGallery: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var tokenIds: [String]
    public var isActiveForRotation: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        tokenIds: [String] = [],
        isActiveForRotation: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.tokenIds = tokenIds
        self.isActiveForRotation = isActiveForRotation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
