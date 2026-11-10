import SwiftUI
import AppKit

/// Top-level sidebar selection targets
public enum LibrarySidebarItem: Hashable, Sendable {
    case allArt
    case owned
    case created
    case collections
    case collection(String)    // contract address
    case customGallery(UUID)
    case objktCuration(String) // galleryId
    case source(UUID)          // specific wallet source
}

/// Format category filter (UI filter, NOT hardcoded tabs)
public enum FormatFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Formats"
    case still = "Still Images"
    case video = "Video & Loops"
    case gif = "Animated GIFs"
    case generative = "Generative Art"
    case audio3d = "3D & Audio"

    public var id: String { rawValue }

    public func matches(_ category: MediaCategory) -> Bool {
        switch self {
        case .all: return true
        case .still: return category == .staticImage || category == .vectorImage
        case .video: return category == .video
        case .gif: return category == .animatedImage
        case .generative: return category == .fxhash || category == .aleatory || category == .bootloader || category == .editArt || category == .interactiveHtml
        case .audio3d: return category == .audio3d
        }
    }
}

/// Sort fields for artwork collection
public enum TokenSortOption: String, CaseIterable, Identifiable, Sendable {
    case dateAcquired = "Date Added"
    case mintDate = "Mint Date (Token ID)"
    case title = "Title (A–Z)"
    case supply = "Edition Size"

    public var id: String { rawValue }
}

/// Direction for sorting
public enum SortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending = "Ascending"
    case descending = "Descending"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .ascending: return "arrow.up"
        case .descending: return "arrow.down"
        }
    }
}

/// Summary of unique contracts in the collection
public struct CollectionContractItem: Identifiable, Hashable, Sendable {
    public var id: String { contract }
    public let contract: String
    public let displayName: String
    public let count: Int
    public let fxhashVersion: String?

    public init(contract: String, displayName: String, count: Int, fxhashVersion: String? = nil) {
        self.contract = contract
        self.displayName = displayName
        self.count = count
        self.fxhashVersion = fxhashVersion
    }

    public var isFxhash: Bool {
        return contract.hasPrefix("fxhash:")
    }

    public var shortContract: String {
        if let v = fxhashVersion {
            return "fxhash \(v)"
        }
        guard contract.count > 10 else { return contract }
        let p = contract.prefix(6)
        let s = contract.suffix(4)
        return "\(p)…\(s)"
    }
}

/// Main desktop library management window
public struct LibraryView: View {
    @State private var sources: [WalletSource] = []
    @State private var tokens: [UnifiedToken] = []
    @State private var galleries: [DesktopGallery] = []
    @State private var objktCurations: [ObjktGallerySummary] = []
    @State private var collectionNames: [String: String] = [:]
    @State private var artistProfiles: [String: ArtistProfile] = [:]
    @State private var fxhashProjects: [String: FxhashProjectInfo] = [:]

    // Cached off-main-thread derived sidebar & filter state
    @State private var ownedCount: Int = 0
    @State private var createdCount: Int = 0
    @State private var cachedUniqueCollections: [CollectionContractItem] = []
    @State private var galleryMatchCounts: [UUID: Int] = [:]
    @State private var hasLoadedDiskCaches: Bool = false
    @State private var filterSortTask: Task<Void, Never>? = nil
    @State private var derivedStatsTask: Task<Void, Never>? = nil
    @State private var backgroundResolveTask: Task<Void, Never>? = nil

    // Mixed Context Collection Scope (In Library vs Entire Collection on-chain)
    @State private var collectionScope: CollectionRotationScope = .inLibrary
    @State private var entireCollectionTokens: [String: [UnifiedToken]] = [:]
    @State private var isFetchingEntireCollection: Bool = false
    @State private var sourceScope: WalletFollowScope = .owned

    @State private var selectedSidebarItem: LibrarySidebarItem = .allArt
    @State private var selectedToken: UnifiedToken?
    @State private var isInspectorPresented: Bool = false
    @ObservedObject private var wallpaperState = DesktopWallpaperState.shared

    // Filters and controls
    @State private var searchText: String = ""
    @State private var collectionSearchText: String = ""
    @State private var selectedFormatFilter: FormatFilter = .all
    @State private var selectedContractFilter: String? = nil
    @State private var sortOption: TokenSortOption = .dateAcquired
    @State private var sortDirection: SortDirection = .descending
    @State private var gridSize: Double = 180
    @State private var displayedTokens: [UnifiedToken] = []
    @State private var renderLimit: Int = 80

    // Wallpaper Matte Settings
    @AppStorage("wallpaperMatteMode") private var matteMode: WallpaperMatteMode = .dynamicArtwork
    @AppStorage("wallpaperCustomHex") private var customHex: String = "#000000"

    // Desktop Wallpaper Rotation State
    @State private var activeRotationTarget: ActiveRotationTarget = .allArt
    @State private var isRotationPaused: Bool = false
    @State private var isRotationShuffle: Bool = true
    @State private var rotationInterval: RotationInterval = .fiveMinutes

    // Sheets & modals
    @State private var isSourceSheetPresented: Bool = false
    @State private var isNewGallerySheetPresented: Bool = false
    @State private var newGalleryName: String = ""
    @State private var newGalleryDesc: String = ""
    @State private var newGalleryType: GalleryType = .smart
    @State private var newGalleryCriteria: GalleryFilterCriteria? = nil
    @State private var newGalleryCreationMode: String = "curated"
    @State private var newGalleryTargetWallet: String = ""
    @State private var newGalleryTargetWalletScope: WalletFollowScope = .created
    @State private var isCreatingSmartFollower: Bool = false
    @State private var tokensToAddToNewGallery: [String] = []
    @State private var isSyncing: Bool = false
    @State private var syncStatusMessage: String?

    private let repository: WalletRepository
    private let onSetWallpaper: (UnifiedToken) -> Void

    public init(
        repository: WalletRepository = WalletRepository(),
        onSetWallpaper: @escaping (UnifiedToken) -> Void = { _ in }
    ) {
        self.repository = repository
        self.onSetWallpaper = onSetWallpaper
    }

    // MARK: - Helpers

    private var selectedGallery: DesktopGallery? {
        if case .customGallery(let gid) = selectedSidebarItem {
            return galleries.first(where: { $0.id == gid })
        }
        return nil
    }

    public func resolveCardArtistName(for token: UnifiedToken) -> String {
        // If viewing an artist-focused gallery, prioritize matching that artist:
        if let crit = selectedGallery?.criteria, let target = crit.targetWallet?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            let targetDomain = crit.targetDomain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for creator in token.creators {
                let cLower = creator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let alias = artistDisplayName(for: creator).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if cLower == target || alias == target || (targetDomain != nil && (cLower == targetDomain || alias == targetDomain)) {
                    let displayName = artistDisplayName(for: creator)
                    let distinctAddrs = Set(token.creators.compactMap { c -> String? in
                        let lower = c.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        return (lower.hasPrefix("tz") || lower.hasPrefix("kt")) ? lower : nil
                    })
                    if distinctAddrs.count > 1 {
                        return "\(displayName) (collab)"
                    }
                    return displayName
                }
            }
        }

        guard let first = token.creators.first else { return "" }
        let primary = artistDisplayName(for: first)
        let distinctAddrs = Set(token.creators.compactMap { c -> String? in
            let lower = c.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return (lower.hasPrefix("tz") || lower.hasPrefix("kt")) ? lower : nil
        })
        if distinctAddrs.count > 1 {
            return "\(primary) +\(distinctAddrs.count - 1)"
        }
        return primary
    }

    public func resolveTargetCreatorAddress(for token: UnifiedToken) -> String? {
        if let crit = selectedGallery?.criteria, let target = crit.targetWallet?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            let targetDomain = crit.targetDomain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for creator in token.creators {
                let cLower = creator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let alias = artistDisplayName(for: creator).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if cLower == target || alias == target || (targetDomain != nil && (cLower == targetDomain || alias == targetDomain)) {
                    return creator
                }
            }
        }
        return token.creators.first
    }

    public func artistDisplayName(for addressOrName: String) -> String {
        return Self.staticArtistDisplayName(for: addressOrName, artistProfiles: artistProfiles)
    }

    public func artistProfile(for addressOrName: String) -> ArtistProfile? {
        return Self.staticArtistProfile(for: addressOrName, artistProfiles: artistProfiles)
    }

    public func resolvedProjectName(for token: UnifiedToken) -> String {
        return Self.staticResolvedProjectName(for: token, fxhashProjects: fxhashProjects)
    }

    public func collectionTokenMatches(token: UnifiedToken, key: String) -> Bool {
        return Self.staticCollectionTokenMatches(token: token, key: key, fxhashProjects: fxhashProjects)
    }

    public func resolvedName(for contract: String) -> String {
        return Self.staticResolvedName(for: contract, collectionNames: collectionNames)
    }

    // MARK: - Pure Static Helpers (Safe Off-Main-Actor)

    private nonisolated static func staticArtistDisplayName(for addressOrName: String, artistProfiles: [String: ArtistProfile]) -> String {
        let trimmed = addressOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profile = artistProfiles[trimmed] ?? artistProfiles[trimmed.lowercased()] {
            return profile.displayName
        }
        guard trimmed.count > 10 else { return trimmed }
        return String(trimmed.prefix(6)) + "…" + String(trimmed.suffix(4))
    }

    private nonisolated static func staticArtistProfile(for addressOrName: String, artistProfiles: [String: ArtistProfile]) -> ArtistProfile? {
        let trimmed = addressOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        return artistProfiles[trimmed] ?? artistProfiles[trimmed.lowercased()]
    }

    private nonisolated static func staticResolvedProjectName(for token: UnifiedToken, fxhashProjects: [String: FxhashProjectInfo]) -> String {
        if let info = fxhashProjects[token.id], let p = info.projectName, !p.isEmpty {
            return p
        }
        return token.fxhashProjectName ?? "fxhash (\(token.fxhashVersion ?? "Generative"))"
    }

    private nonisolated static func staticCollectionTokenMatches(token: UnifiedToken, key: String, fxhashProjects: [String: FxhashProjectInfo]) -> Bool {
        if key.hasPrefix("fxhash:") {
            let targetProj = String(key.dropFirst(7)).lowercased()
            return token.isFxhash && (staticResolvedProjectName(for: token, fxhashProjects: fxhashProjects).lowercased() == targetProj)
        }
        return token.contract.caseInsensitiveCompare(key) == .orderedSame
    }

    private nonisolated static func staticResolvedName(for contract: String, collectionNames: [String: String]) -> String {
        if contract.hasPrefix("fxhash:") {
            return String(contract.dropFirst(7))
        }
        let lower = contract.lowercased()
        if let name = collectionNames[contract] ?? collectionNames[lower] {
            return name
        }
        return staticDefaultContractAlias(for: contract)
    }

    private nonisolated static func staticIsTokenCreatedByUser(_ token: UnifiedToken, sourceAddresses: Set<String>) -> Bool {
        if token.isCreated { return true }
        for creator in token.creators {
            if sourceAddresses.contains(creator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return true
            }
        }
        return false
    }

    // MARK: - Asynchronous Background Filtering, Sorting & Derived Stats

    private func updateDisplayedTokens() {
        filterSortTask?.cancel()
        renderLimit = 80

        let snapTokens = tokens
        let snapSources = sources
        let snapGalleries = galleries
        let snapEntire = entireCollectionTokens
        let snapColNames = collectionNames
        let snapArtistProfiles = artistProfiles
        let snapFxhash = fxhashProjects
        let snapSidebar = selectedSidebarItem
        let snapColScope = collectionScope
        let snapSrcScope = sourceScope
        let snapSearch = searchText
        let snapFormat = selectedFormatFilter
        let snapContract = selectedContractFilter
        let snapSort = sortOption
        let snapDir = sortDirection

        filterSortTask = Task.detached(priority: .userInitiated) {
            if Task.isCancelled { return }
            let sourceAddresses = Set(snapSources.compactMap { $0.walletAddress?.lowercased() })

            // 1. Filter by top-level sidebar selection
            var baseTokens: [UnifiedToken]
            switch snapSidebar {
            case .allArt:
                baseTokens = snapTokens
            case .owned:
                baseTokens = snapTokens.filter { $0.isOwned }
            case .created:
                baseTokens = snapTokens.filter { $0.isCreated || Self.staticIsTokenCreatedByUser($0, sourceAddresses: sourceAddresses) }
            case .collections:
                baseTokens = snapTokens
            case .customGallery(let gid):
                if let gallery = snapGalleries.first(where: { $0.id == gid }) {
                    baseTokens = gallery.matchingTokens(from: snapTokens, artistDisplayName: {
                        Self.staticArtistDisplayName(for: $0, artistProfiles: snapArtistProfiles)
                    })
                } else {
                    baseTokens = []
                }
            case .objktCuration(let cid):
                baseTokens = snapTokens.filter { $0.rawMetadata?["curationId"] == cid }
            case .collection(let key):
                if snapColScope == .entireCollection {
                    if let entire = snapEntire[key] ?? snapEntire[key.lowercased()], !entire.isEmpty {
                        baseTokens = entire
                    } else {
                        baseTokens = snapTokens.filter { Self.staticCollectionTokenMatches(token: $0, key: key, fxhashProjects: snapFxhash) }
                    }
                } else {
                    baseTokens = snapTokens.filter { Self.staticCollectionTokenMatches(token: $0, key: key, fxhashProjects: snapFxhash) }
                }
            case .source(let sid):
                if let src = snapSources.first(where: { $0.id == sid }), let addr = src.walletAddress?.lowercased() {
                    if snapSrcScope == .created {
                        baseTokens = snapTokens.filter { t in
                            t.creators.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == addr }
                        }
                    } else {
                        baseTokens = snapTokens.filter { t in
                            t.isOwned && (t.rawMetadata?["sourceWallet"]?.lowercased() == addr || snapSources.count == 1)
                        }
                    }
                } else {
                    baseTokens = []
                }
            }

            if Task.isCancelled { return }

            // 2. Filter by search text
            if !snapSearch.isEmpty {
                baseTokens = baseTokens.filter { token in
                    token.name.localizedCaseInsensitiveContains(snapSearch) ||
                    token.creators.contains(where: { creator in
                        creator.localizedCaseInsensitiveContains(snapSearch) ||
                        Self.staticArtistDisplayName(for: creator, artistProfiles: snapArtistProfiles).localizedCaseInsensitiveContains(snapSearch) ||
                        (Self.staticArtistProfile(for: creator, artistProfiles: snapArtistProfiles)?.tzdomain?.localizedCaseInsensitiveContains(snapSearch) ?? false) ||
                        (Self.staticArtistProfile(for: creator, artistProfiles: snapArtistProfiles)?.twitterHandle?.localizedCaseInsensitiveContains(snapSearch) ?? false)
                    }) ||
                    token.contract.localizedCaseInsensitiveContains(snapSearch) ||
                    Self.staticResolvedName(for: token.contract, collectionNames: snapColNames).localizedCaseInsensitiveContains(snapSearch) ||
                    token.tokenId.contains(snapSearch)
                }
            }

            // 3. Filter by format filter
            if snapFormat != .all {
                baseTokens = baseTokens.filter { snapFormat.matches($0.mediaCategory) }
            }

            // 4. Filter by collection filter
            if let contractFilter = snapContract, !contractFilter.isEmpty {
                let lowerFilter = contractFilter.lowercased()
                baseTokens = baseTokens.filter { $0.contract.lowercased() == lowerFilter }
            }

            if Task.isCancelled { return }

            // 5. Schwartzian Transform Sort (computes acquiredDate ONCE per token, not O(N log N) times)
            let isAsc = (snapDir == .ascending)
            let sortedTokens: [UnifiedToken]
            switch snapSort {
            case .dateAcquired:
                let keyed = baseTokens.map { token -> (token: UnifiedToken, ts: TimeInterval, idInt: Int) in
                    let ts = (token.acquiredDate ?? Date.distantPast).timeIntervalSinceReferenceDate
                    return (token, ts, Int(token.tokenId) ?? 0)
                }
                let sortedKeyed = keyed.sorted { a, b in
                    if a.ts != b.ts {
                        return isAsc ? (a.ts < b.ts) : (a.ts > b.ts)
                    }
                    return isAsc ? (a.idInt < b.idInt) : (a.idInt > b.idInt)
                }
                sortedTokens = sortedKeyed.map(\.token)

            case .mintDate:
                let keyed = baseTokens.map { ($0, Int($0.tokenId) ?? 0) }
                sortedTokens = keyed.sorted { isAsc ? ($0.1 < $1.1) : ($0.1 > $1.1) }.map(\.0)

            case .title:
                sortedTokens = baseTokens.sorted { a, b in
                    let compare = a.name.localizedCaseInsensitiveCompare(b.name)
                    return isAsc ? (compare == .orderedAscending) : (compare == .orderedDescending)
                }

            case .supply:
                sortedTokens = baseTokens.sorted { a, b in
                    let supA = a.supply ?? 1
                    let supB = b.supply ?? 1
                    return isAsc ? (supA < supB) : (supA > supB)
                }
            }

            if Task.isCancelled { return }
            await MainActor.run {
                self.displayedTokens = sortedTokens
            }
        }
    }

    /// Computes ownedCount, createdCount, uniqueCollections, and gallery match counts off the main thread
    private func recomputeDerivedStats() {
        derivedStatsTask?.cancel()

        let snapTokens = tokens
        let snapSources = sources
        let snapGalleries = galleries
        let snapColNames = collectionNames
        let snapArtistProfiles = artistProfiles
        let snapFxhash = fxhashProjects
        let snapSidebar = selectedSidebarItem
        let snapSrcScope = sourceScope

        derivedStatsTask = Task.detached(priority: .utility) {
            if Task.isCancelled { return }
            let sourceAddresses = Set(snapSources.compactMap { $0.walletAddress?.lowercased() })

            var owned = 0
            var created = 0
            for t in snapTokens {
                if t.isOwned { owned += 1 }
                if t.isCreated || Self.staticIsTokenCreatedByUser(t, sourceAddresses: sourceAddresses) { created += 1 }
            }

            // Compute gallery match counts
            var gCounts: [UUID: Int] = [:]
            for gallery in snapGalleries {
                if Task.isCancelled { return }
                gCounts[gallery.id] = gallery.matchingTokens(from: snapTokens, artistDisplayName: {
                    Self.staticArtistDisplayName(for: $0, artistProfiles: snapArtistProfiles)
                }).count
            }

            // Compute unique collections for current sidebar scope
            var normalCounts: [String: Int] = [:]
            var fxhashCounts: [String: (count: Int, version: String?)] = [:]

            let scopedTokens: [UnifiedToken]
            switch snapSidebar {
            case .created:
                scopedTokens = snapTokens.filter { $0.isCreated || Self.staticIsTokenCreatedByUser($0, sourceAddresses: sourceAddresses) }
            case .owned:
                scopedTokens = snapTokens.filter { $0.isOwned }
            case .customGallery(let gid):
                if let gallery = snapGalleries.first(where: { $0.id == gid }) {
                    scopedTokens = gallery.matchingTokens(from: snapTokens, artistDisplayName: {
                        Self.staticArtistDisplayName(for: $0, artistProfiles: snapArtistProfiles)
                    })
                } else {
                    scopedTokens = []
                }
            case .objktCuration(let cid):
                scopedTokens = snapTokens.filter { $0.rawMetadata?["curationId"] == cid }
            case .source(let sid):
                if let src = snapSources.first(where: { $0.id == sid }), let addr = src.walletAddress?.lowercased() {
                    if snapSrcScope == .created {
                        scopedTokens = snapTokens.filter { t in
                            t.creators.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == addr }
                        }
                    } else {
                        scopedTokens = snapTokens.filter { t in
                            t.isOwned && (t.rawMetadata?["sourceWallet"]?.lowercased() == addr || snapSources.count == 1)
                        }
                    }
                } else {
                    scopedTokens = []
                }
            default:
                scopedTokens = snapTokens
            }

            for t in scopedTokens {
                if t.isFxhash {
                    let projName = Self.staticResolvedProjectName(for: t, fxhashProjects: snapFxhash)
                    let current = fxhashCounts[projName] ?? (0, t.fxhashVersion)
                    fxhashCounts[projName] = (current.count + 1, t.fxhashVersion ?? current.version)
                } else {
                    normalCounts[t.contract, default: 0] += 1
                }
            }

            var items: [CollectionContractItem] = []
            items.reserveCapacity(normalCounts.count + fxhashCounts.count)
            for (contract, count) in normalCounts {
                items.append(CollectionContractItem(
                    contract: contract,
                    displayName: Self.staticResolvedName(for: contract, collectionNames: snapColNames),
                    count: count
                ))
            }
            for (projName, val) in fxhashCounts {
                items.append(CollectionContractItem(
                    contract: "fxhash:\(projName)",
                    displayName: projName,
                    count: val.count,
                    fxhashVersion: val.version
                ))
            }
            let sortedItems = items.sorted { $0.count > $1.count }

            if Task.isCancelled { return }
            await MainActor.run {
                self.ownedCount = owned
                self.createdCount = created
                self.galleryMatchCounts = gCounts
                self.cachedUniqueCollections = sortedItems
            }
        }
    }

    private nonisolated static func staticDefaultContractAlias(for contract: String) -> String {
        let lower = contract.lowercased()
        if lower == "kt1kea8z6vwxdjrvqtmraedvzsvxat3khace" { return "fxhash GENTK v1" }
        if lower == "kt1u6ehmng3rqgzgwrjvm31tymgwgymo61gk" || lower == "kt1u6ehmnxjtkvawj4thczg4fsdahc21ssvi" { return "fxhash GENTK v2" }
        if lower == "kt1efsnuqwlacdq3maa3gkpjtrmmqqes2nuv" || lower == "kt1efsnuqwlawdd3o4pvfux1cah5gmdtrrvr" { return "fx(params)" }
        if lower == "kt1rj6pbjhpwc3m5rw5s2nbmefwbuwbdxton" { return "hic et nunc" }
        if lower == "kt1xacf6gkjfnkg3qmpfn6gep53momvjkj1e" { return "open objkt" }
        if lower == "kt1czvsa18hndyupv9ncxy3qj7p8yfdzkvqv" { return "Mooncakes" }
        if lower == "kt1dck1a29voepg9mgcgowngenjv6etwpbyq" { return "Life List of an AI Birder" }
        if lower == "kt1rg7tkpgj7z42rkdhjcjzfxggeqtaqnepp" { return "Just Failed Fantasy" }
        if lower == "kt1ft6ypzbepauv6btjq21cmzjgtcpnzmwh" { return "WTF IS A HORSE?" }
        if lower == "kt1svctvagpukmunevbfuxhk9ixckbpw5f13h" { return "Playing With Skulls" }
        if lower == "kt1thfytvz3k1qhsy2v77kjmdrnjebzm3mzg" { return "Pepoles Advent Calendar" }
        if lower == "kt1v15gktzmo7h9azgvwcbjqqnnjnzn1agsc" { return "Super Chumbino Tezos Club 2026" }
        if lower == "kt1vlvgtw6ukwzmipan8sncomjicitqbgf6" { return "Long Story Short" }
        if lower == "kt1gez9shjdsg4nmtdktpvjdic3cf3bkzupsc" { return "DOOMBUDS" }
        if lower == "kt1htqeasguu2jxfqw1px2fgsvmw yks4r9pw" { return "Not" }
        if lower == "kt1kvk31zfry3nxam6ng7vnnfanhkckjkqnq" { return "Treasure Chest" }
        if lower == "kt1gbzmsxmnkjxgmdmlbugpflyupmulsmwks" { return "Tezos Domains" }
        if lower == "kt1vivwovfgscdaxjwoovejm1aysgz7s2tz" { return "Tezotopia NFT Registry" }
        if lower == "kt1mchcpyoagydsr8y4rpkrx7b7vokmndbbh" { return "Misfits" }
        if lower == "kt1rron7yf6yj7rm7afybc8zydvk3udxmupm" { return "TezTowers" }
        if lower == "kt1st7grn4lwxb8y6bvgq8sdjgvqhd8sjghb" { return "Tez Frenz" }
        if lower == "kt1cfdgefo44dn64jgtfhf2yqrzktkg1yfxm4" { return "House of Skratz" }
        return String(contract.prefix(8)) + "…" + String(contract.suffix(4))
    }

    // MARK: - View Body

    public var body: some View {
        NavigationSplitView {
            // Sidebar Navigation
            List(selection: $selectedSidebarItem) {
                // Section: Library Core
                Section("Library") {
                    HStack {
                        Label("All Art", systemImage: "photo.stack")
                        Spacer()
                        Text("\(tokens.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(LibrarySidebarItem.allArt)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSidebarItem = .allArt
                        selectedContractFilter = nil
                    }

                    HStack {
                        Label("Owned", systemImage: "tray.full")
                        Spacer()
                        Text("\(ownedCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(LibrarySidebarItem.owned)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSidebarItem = .owned
                        selectedContractFilter = nil
                    }

                    HStack {
                        Label("Created", systemImage: "paintpalette")
                        Spacer()
                        Text("\(createdCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(LibrarySidebarItem.created)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSidebarItem = .created
                        selectedContractFilter = nil
                    }

                    HStack {
                        Label("Collections", systemImage: "rectangle.stack")
                        Spacer()
                        Text("\(cachedUniqueCollections.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(LibrarySidebarItem.collections)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSidebarItem = .collections
                    }
                }

                // Section: desKTop Galleries (Custom Playlists)
                Section {
                    ForEach(galleries) { gallery in
                        let matchCount = galleryMatchCounts[gallery.id] ?? 0
                        HStack(spacing: 6) {
                            Label(gallery.name, systemImage: gallery.isSmart ? "wand.and.stars" : "sparkles.rectangle.stack")
                                .lineLimit(1)
                            Spacer()
                            if gallery.isSmart {
                                Text("SMART")
                                    .font(.system(size: 7, weight: .black))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.18))
                                    .foregroundColor(.purple)
                                    .cornerRadius(3)
                            }
                            if gallery.isActiveForRotation {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                    .help("Active rotation gallery")
                            }
                            Text("\(matchCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .tag(LibrarySidebarItem.customGallery(gallery.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSidebarItem = .customGallery(gallery.id)
                        }
                        .contextMenu {
                            Button(gallery.isActiveForRotation ? "Deactivate Rotation" : "Set Active for Rotation") {
                                Task {
                                    try? await repository.setActiveGallery(id: gallery.isActiveForRotation ? nil : gallery.id)
                                    await reloadData()
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                Task {
                                    try? await repository.deleteGallery(id: gallery.id)
                                    await reloadData()
                                }
                            } label: {
                                Label("Delete Gallery", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("desKTop Galleries")
                        Spacer()
                        Button(action: {
                            newGalleryName = ""
                            newGalleryDesc = ""
                            isNewGallerySheetPresented = true
                        }) {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Create new desKTop Gallery")
                    }
                }

                // Section: objkt Curations
                if !objktCurations.isEmpty {
                    Section("objkt Curations") {
                        ForEach(objktCurations) { curation in
                            HStack {
                                Label(curation.name, systemImage: "square.grid.2x2")
                                    .lineLimit(1)
                                Spacer()
                                Text("\(curation.itemsCount)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tag(LibrarySidebarItem.objktCuration(curation.galleryId))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSidebarItem = .objktCuration(curation.galleryId)
                            }
                            .help(curation.description ?? curation.name)
                        }
                    }
                }

                // Section: Sources
                Section("Sources") {
                    ForEach(sources) { source in
                        HStack {
                            Circle()
                                .fill(source.isEnabled ? Color.green : Color.gray)
                                .frame(width: 7, height: 7)
                            Text(source.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text("\(source.tokenCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .tag(LibrarySidebarItem.source(source.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSidebarItem = .source(source.id)
                        }
                        .contextMenu {
                            Button("View Owned Pieces") {
                                sourceScope = .owned
                                selectedSidebarItem = .source(source.id)
                            }
                            Button("View Created Pieces") {
                                sourceScope = .created
                                selectedSidebarItem = .source(source.id)
                            }
                            Divider()
                            Button("Follow Owned as Smart Gallery") {
                                Task {
                                    _ = try? await repository.followCollector(
                                        addressOrDomain: source.walletAddress ?? source.displayName,
                                        displayName: "Collected by \(source.displayName)"
                                    )
                                    await reloadData()
                                }
                            }
                            Button("Follow Created as Smart Gallery") {
                                Task {
                                    _ = try? await repository.followCreator(
                                        addressOrDomain: source.walletAddress ?? source.displayName,
                                        displayName: "Created by \(source.displayName)"
                                    )
                                    await reloadData()
                                }
                            }
                        }
                    }

                    Button(action: { isSourceSheetPresented = true }) {
                        Label("Manage Sources…", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isSourceSheetPresented = true }) {
                        Label("Add Source", systemImage: "plus")
                    }
                    .help("Add a Tezos wallet, domain, or collection")
                }
            }
        } detail: {
            // Main Content Area: Collections Browser OR Artwork Grid
            Group {
                if case .collections = selectedSidebarItem {
                    collectionsBrowserView
                } else {
                    artworksGridView
                }
            }
            .inspector(isPresented: $isInspectorPresented) {
                if let token = selectedToken {
                    let colKey = token.isFxhash ? "fxhash:\(resolvedProjectName(for: token))" : token.contract
                    let colDisplay = token.isFxhash ? resolvedProjectName(for: token) : resolvedName(for: token.contract)
                    let colCount = tokens.filter { collectionTokenMatches(token: $0, key: colKey) }.count
                    let isColMyRotating: Bool = {
                        if case .collection(let activeContract, _, let scope) = activeRotationTarget {
                            return activeContract.caseInsensitiveCompare(colKey) == .orderedSame && scope == .inLibrary
                        }
                        return false
                    }()
                    let isColEntireRotating: Bool = {
                        if case .collection(let activeContract, _, let scope) = activeRotationTarget {
                            return activeContract.caseInsensitiveCompare(colKey) == .orderedSame && scope == .entireCollection
                        }
                        return false
                    }()

                    let targetCreator = resolveTargetCreatorAddress(for: token)
                    TokenInspectorView(
                        token: token,
                        collectionName: colDisplay,
                        collectionTokensCount: colCount,
                        artistProfile: targetCreator.flatMap { artistProfile(for: $0) },
                        artistDisplayName: targetCreator.map { artistDisplayName(for: $0) } ?? (token.creators.first.map { artistDisplayName(for: $0) } ?? "Unknown"),
                        fxhashProjectInfo: fxhashProjects[token.id],
                        isLiveOnDesktop: wallpaperState.liveTokenId == token.id,
                        isApplyingToDesktop: wallpaperState.loadingTokenId == token.id,
                        desktopPhase: wallpaperState.phase,
                        isCollectionMyRotating: isColMyRotating,
                        isCollectionEntireRotating: isColEntireRotating,
                        galleries: galleries,
                        matteMode: $matteMode,
                        customHex: $customHex,
                        onSetWallpaper: {
                            onSetWallpaper(token)
                        },
                        onRotateCollectionMy: {
                            startRotatingCurrentScope(.collection(contract: colKey, displayName: colDisplay, scope: .inLibrary))
                        },
                        onRotateCollectionEntire: {
                            loadEntireCollection(for: colKey)
                            startRotatingCurrentScope(.collection(contract: colKey, displayName: colDisplay, scope: .entireCollection))
                        },
                        onAddToGallery: { gid in
                            Task {
                                try? await repository.addTokenToGallery(tokenId: token.id, galleryId: gid)
                                await reloadData()
                            }
                        },
                        onFilterByCollection: { contract in
                            selectedSidebarItem = .collection(contract)
                        },
                        onFollowArtistCreated: { addr, name in
                            Task {
                                let g = try? await repository.followCreator(addressOrDomain: addr, displayName: "Created by \(name)")
                                await reloadData()
                                if let g = g {
                                    selectedSidebarItem = .customGallery(g.id)
                                }
                            }
                        },
                        onFollowArtistOwned: { addr, name in
                            Task {
                                let g = try? await repository.followCollector(addressOrDomain: addr, displayName: "Collected by \(name)")
                                await reloadData()
                                if let g = g {
                                    selectedSidebarItem = .customGallery(g.id)
                                }
                            }
                        }
                    )
                } else {
                    inspectorPlaceholderView
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 330, max: 400)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isInspectorPresented.toggle() }) {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help("Toggle Artwork Details Inspector")
                }
            }
        }
        .task {
            await reloadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("didReopenLibraryWindow"))) { _ in
            Task {
                await reloadData(skipNetworkResolve: true)
            }
        }
        .onChange(of: searchText) { _ in updateDisplayedTokens() }
        .onChange(of: selectedSidebarItem) { _ in
            updateDisplayedTokens()
            recomputeDerivedStats()
        }
        .onChange(of: selectedFormatFilter) { _ in updateDisplayedTokens() }
        .onChange(of: selectedContractFilter) { _ in updateDisplayedTokens() }
        .onChange(of: sortOption) { _ in updateDisplayedTokens() }
        .onChange(of: sortDirection) { _ in updateDisplayedTokens() }
        .onChange(of: sourceScope) { _ in
            updateDisplayedTokens()
            recomputeDerivedStats()
        }
        .onChange(of: collectionScope) { _ in updateDisplayedTokens() }
        .onChange(of: galleries) { _ in
            updateDisplayedTokens()
            recomputeDerivedStats()
        }
        .sheet(isPresented: $isSourceSheetPresented) {
            SourceManagementSheet(repository: repository) {
                Task {
                    await reloadData()
                }
            }
        }
        .sheet(isPresented: $isNewGallerySheetPresented) {
            newGallerySheet
        }
    }

    // MARK: - Subviews: Artworks Grid

    private var artworksGridView: some View {
        VStack(spacing: 0) {
            // Collection mixed-context header & scope selector
            if case .collection(let colKey) = selectedSidebarItem {
                collectionScopeHeader(for: colKey)
            }

            // Source wallet scope header & follower
            if case .source(let sid) = selectedSidebarItem, let src = sources.first(where: { $0.id == sid }) {
                sourceScopeHeader(for: src)
            }

            // Desktop Rotation Player Header Bar
            desktopRotationPlayerBar

            // Secondary Filter Toolbar
            filterToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

            Divider()

            // Main Art Grid
            ScrollView {
                if displayedTokens.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: gridSize, maximum: gridSize * 1.5), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(displayedTokens.prefix(renderLimit)) { token in
                            let cardColName = token.isFxhash ? resolvedProjectName(for: token) : resolvedName(for: token.contract)
                            TokenCardView(
                                token: token,
                                collectionName: cardColName,
                                artistName: resolveCardArtistName(for: token),
                                isSelected: selectedToken?.id == token.id,
                                isLiveOnDesktop: wallpaperState.liveTokenId == token.id,
                                isApplyingToDesktop: wallpaperState.loadingTokenId == token.id,
                                galleries: galleries,
                                onSelect: {
                                    selectedToken = token
                                },
                                onSetAsWallpaper: {
                                    onSetWallpaper(token)
                                },
                                onAddToGallery: { gid in
                                    Task {
                                        try? await repository.addTokenToGallery(tokenId: token.id, galleryId: gid)
                                        await reloadData()
                                    }
                                },
                                onFilterByCollection: { _ in
                                    let key = token.isFxhash ? "fxhash:\(resolvedProjectName(for: token))" : token.contract
                                    selectedSidebarItem = .collection(key)
                                },
                                onRemoveFromCurrentGallery: {
                                    if case .customGallery(let gid) = selectedSidebarItem {
                                        Task {
                                            try? await repository.removeTokenFromGallery(tokenId: token.id, galleryId: gid)
                                            await reloadData()
                                        }
                                    }
                                }
                            )
                        }

                        if renderLimit < displayedTokens.count {
                            Color.clear
                                .frame(height: 30)
                                .onAppear {
                                    renderLimit = min(displayedTokens.count, renderLimit + 60)
                                }
                        }
                    }
                    .padding(16)
                }
            }
            .searchable(text: $searchText, prompt: "Search title, creator, or collection…")
        }
        .navigationTitle(navigationTitleString)
    }

    // MARK: - Collection Mixed-Context Scope Header

    private func collectionScopeHeader(for colKey: String) -> some View {
        let isFxhash = colKey.hasPrefix("fxhash:")
        let projName = isFxhash ? String(colKey.dropFirst(7)) : resolvedName(for: colKey)
        let myCount = tokens.filter { collectionTokenMatches(token: $0, key: colKey) }.count
        let entireList = entireCollectionTokens[colKey] ?? entireCollectionTokens[colKey.lowercased()]
        let entireCount = entireList?.count

        let isCurrentScopeRotating: Bool = {
            if case .collection(let activeContract, _, let activeScope) = activeRotationTarget {
                return activeContract.caseInsensitiveCompare(colKey) == .orderedSame && activeScope == collectionScope
            }
            return false
        }()

        return VStack(spacing: 8) {
            // Row 1: Breadcrumb + Marketplace Links
            HStack(spacing: 8) {
                Button(action: {
                    selectedSidebarItem = .collections
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Collections")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .buttonStyle(.link)

                Text("/")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.caption)

                Text(projName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if isFxhash {
                    Text("fxhash Generative Project")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                }

                Spacer()

                // Marketplace direct link
                if isFxhash {
                    let firstToken = tokens.first(where: { collectionTokenMatches(token: $0, key: colKey) })
                    if let pId = fxhashProjects[firstToken?.id ?? ""]?.issuerId ?? firstToken?.fxhashProjectId {
                        Button(action: {
                            if let url = URL(string: "https://objkt.com/collections/fxhash/projects/\(pId)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("Project on objkt", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.link)

                        Button(action: {
                            if let url = URL(string: "https://www.fxhash.xyz/generative/slug/\(pId)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("Project on fxhash", systemImage: "cube")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                } else {
                    Button(action: {
                        if let url = URL(string: "https://objkt.com/collections/\(colKey)") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Label("Collection on objkt", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
            }

            // Row 2: Mixed-Context Scope Selector & 1-Click Desktop Rotation
            HStack(spacing: 12) {
                // Segmented Scope Switcher
                Picker("Scope", selection: $collectionScope) {
                    Text("In My Library (\(myCount))")
                        .tag(CollectionRotationScope.inLibrary)

                    if let total = entireCount {
                        Text("Entire Collection (\(total))")
                            .tag(CollectionRotationScope.entireCollection)
                    } else if isFetchingEntireCollection {
                        Text("Entire Collection (Loading…)")
                            .tag(CollectionRotationScope.entireCollection)
                    } else {
                        Text("Entire Collection (Explore)")
                            .tag(CollectionRotationScope.entireCollection)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .onChange(of: collectionScope) { _, newScope in
                    if newScope == .entireCollection {
                        loadEntireCollection(for: colKey)
                    }
                }

                if isFetchingEntireCollection {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading on-chain pieces…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Dual Desktop Rotation Action
                Button(action: {
                    startRotatingCurrentScope(.collection(
                        contract: colKey,
                        displayName: projName,
                        scope: collectionScope
                    ))
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCurrentScopeRotating ? "checkmark.circle.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isCurrentScopeRotating ? "Rotating on Desktop" : (collectionScope == .entireCollection ? "Rotate Entire Collection" : "Rotate My Pieces (\(myCount))"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isCurrentScopeRotating ? Color.green : Color.accentColor)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
    }

    // MARK: - Source Wallet Follower Header

    @ViewBuilder
    private func sourceScopeHeader(for src: WalletSource) -> some View {
        let addr = src.walletAddress?.lowercased() ?? ""
        let ownedCount = tokens.filter { $0.isOwned && ($0.rawMetadata?["sourceWallet"]?.lowercased() == addr || sources.count == 1) }.count
        let createdCount = tokens.filter { t in
            t.creators.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == addr }
        }.count

        HStack(spacing: 12) {
            Circle()
                .fill(src.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(src.displayName)
                    .font(.system(size: 13, weight: .bold))
                if let a = src.walletAddress {
                    Text(String(a.prefix(6)) + "…" + String(a.suffix(4)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Dual Scope: Owned vs Created
            Picker("Wallet Scope", selection: $sourceScope) {
                Text("Owned (\(ownedCount))").tag(WalletFollowScope.owned)
                Text("Created (\(createdCount))").tag(WalletFollowScope.created)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer()

            // 1-Click Follow as Smart Gallery
            Button(action: {
                Task {
                    let title = sourceScope == .created ? "Created by \(src.displayName)" : "Collected by \(src.displayName)"
                    let crit = GalleryFilterCriteria(targetWallet: src.walletAddress ?? src.displayName, walletScope: sourceScope)
                    let g = try? await repository.createSmartGallery(name: title, description: "Smart Gallery tracking \(src.displayName)", criteria: crit)
                    await reloadData()
                    if let g = g {
                        selectedSidebarItem = .customGallery(g.id)
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .bold))
                    Text(sourceScope == .created ? "Follow Created as Smart Gallery" : "Follow Owned as Smart Gallery")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
    }

    // MARK: - Desktop Rotation Player Bar

    private var desktopRotationPlayerBar: some View {
        let currentTarget = currentActiveRotationTargetForCurrentView()
        let isCurrentScopeRotating = isScopeCurrentlyRotating(currentTarget)

        return HStack(spacing: 12) {
            // Left: Scope & Live Status Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(isCurrentScopeRotating ? (isRotationPaused ? Color.orange : Color.green) : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)

                Text(currentScopeTitle)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text("(\(displayedTokens.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if case .loading(_, let msg) = wallpaperState.phase {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(msg)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(4)
                } else if case .failed(_, let errMsg) = wallpaperState.phase {
                    Text(errMsg)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.10))
                        .cornerRadius(4)
                } else if isCurrentScopeRotating {
                    Text(isRotationPaused ? "PAUSED" : "ROTATING")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(isRotationPaused ? .orange : .green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((isRotationPaused ? Color.orange : Color.green).opacity(0.12))
                        .cornerRadius(4)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // Right: Player Controls
            if isCurrentScopeRotating {
                HStack(spacing: 6) {
                    // Next Wallpaper Button
                    Button(action: {
                        NotificationCenter.default.post(name: .didRequestNextWallpaper, object: nil)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Next")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Advance to next wallpaper immediately")

                    // Pause / Resume Toggle
                    Button(action: {
                        Task {
                            try? await repository.setRotationPaused(!isRotationPaused)
                            await reloadData()
                        }
                    }) {
                        Image(systemName: isRotationPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isRotationPaused ? "Resume auto-rotation" : "Pause auto-rotation")

                    // Interval Menu
                    Menu {
                        ForEach(RotationInterval.allCases) { interval in
                            Button(interval.displayName) {
                                rotationInterval = interval
                                Task {
                                    try? await repository.setRotationInterval(interval.rawValue)
                                    await reloadData()
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                            Text(rotationInterval.compactLabel)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(5)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    // Shuffle Toggle
                    Button(action: {
                        Task {
                            try? await repository.setRotationShuffle(!isRotationShuffle)
                            await reloadData()
                        }
                    }) {
                        Image(systemName: isRotationShuffle ? "shuffle" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: isRotationShuffle ? .black : .regular))
                            .foregroundColor(isRotationShuffle ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .help(isRotationShuffle ? "Shuffle: ON (random order)" : "Shuffle: OFF (sequential order)")
                }
                .fixedSize()
            } else {
                HStack(spacing: 6) {
                    Button(action: {
                        saveCurrentScopeAsGallery()
                    }) {
                        Label("Save Gallery", systemImage: "plus.rectangle.on.rectangle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        startRotatingCurrentScope(currentTarget)
                    }) {
                        Label("Rotate on Desktop", systemImage: "play.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrentScopeRotating ? Color.green.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrentScopeRotating ? Color.green.opacity(0.25) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func currentActiveRotationTargetForCurrentView() -> ActiveRotationTarget {
        switch selectedSidebarItem {
        case .allArt:
            return .allArt
        case .owned:
            return .owned
        case .created:
            return .created
        case .collection(let contract):
            let baseName = contract.hasPrefix("fxhash:") ? String(contract.dropFirst(7)) : resolvedName(for: contract)
            return .collection(contract: contract, displayName: baseName, scope: collectionScope)
        case .customGallery(let gid):
            let name = galleries.first(where: { $0.id == gid })?.name ?? "Gallery"
            return .customGallery(id: gid, name: name)
        case .objktCuration(let cid):
            let name = objktCurations.first(where: { $0.galleryId == cid })?.name ?? "Curation"
            return .objktCuration(id: cid, name: name)
        case .source(let sid):
            return (sourceScope == .created) ? .created : .owned
        case .collections:
            return .allArt
        }
    }

    private func isScopeCurrentlyRotating(_ target: ActiveRotationTarget) -> Bool {
        switch (target, activeRotationTarget) {
        case (.allArt, .allArt):
            return true
        case (.owned, .owned):
            return true
        case (.created, .created):
            return true
        case (.collection(let c1, _, let s1), .collection(let c2, _, let s2)):
            return c1.caseInsensitiveCompare(c2) == .orderedSame && s1 == s2
        case (.customGallery(let id1, _), .customGallery(let id2, _)):
            return id1 == id2
        case (.objktCuration(let id1, _), .objktCuration(let id2, _)):
            return id1 == id2
        default:
            return false
        }
    }

    private var currentScopeTitle: String {
        switch selectedSidebarItem {
        case .allArt:
            return "All Art"
        case .owned:
            return "Owned Art"
        case .created:
            return "Created Art"
        case .collection(let contract):
            let baseName = contract.hasPrefix("fxhash:") ? String(contract.dropFirst(7)) : resolvedName(for: contract)
            return collectionScope == .entireCollection ? "Entire \(baseName)" : "My \(baseName)"
        case .customGallery(let gid):
            return galleries.first(where: { $0.id == gid })?.name ?? "Gallery"
        case .objktCuration(let cid):
            return objktCurations.first(where: { $0.galleryId == cid })?.name ?? "Curation"
        case .source(let sid):
            let srcName = sources.first(where: { $0.id == sid })?.displayName ?? "Source"
            return (sourceScope == .created) ? "\(srcName) (Created)" : "\(srcName) (Owned)"
        case .collections:
            return "Collections"
        }
    }

    private func startRotatingCurrentScope(_ target: ActiveRotationTarget) {
        Task {
            try? await repository.setActiveRotationTarget(target)
            try? await repository.setRotationPaused(false)
            await reloadData()
        }
    }

    private func saveCurrentScopeAsGallery() {
        tokensToAddToNewGallery = displayedTokens.map(\.id)
        newGalleryName = currentScopeTitle

        var crit = GalleryFilterCriteria()
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            crit.searchText = searchText
        }
        if selectedFormatFilter != .all {
            crit.formatFilter = selectedFormatFilter.rawValue
        }
        switch selectedSidebarItem {
        case .owned:
            crit.sourceScope = "owned"
        case .created:
            crit.sourceScope = "created"
        case .collection(let contract):
            crit.collectionKey = contract
        default:
            break
        }

        let hasActiveRules = (crit.searchText != nil || crit.formatFilter != nil || crit.collectionKey != nil || crit.sourceScope != nil)
        newGalleryCriteria = hasActiveRules ? crit : nil
        newGalleryType = hasActiveRules ? .smart : .manual
        newGalleryDesc = hasActiveRules ? "Dynamic smart gallery matching \(currentScopeTitle) filters" : "Curated gallery with \(tokensToAddToNewGallery.count) artworks"
        isNewGallerySheetPresented = true
    }

    // MARK: - Subviews: Dedicated Collections Browser

    private var collectionsBrowserView: some View {
        VStack(spacing: 0) {
            // Collection search & header bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Filter collections by name or contract address…", text: $collectionSearchText)
                    .textFieldStyle(.plain)

                if !collectionSearchText.isEmpty {
                    Button(action: { collectionSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(filteredCollections.count) collections")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            // If a collection is currently rotating, show banner
            if case .collection(_, let displayName, let scope) = activeRotationTarget {
                HStack(spacing: 10) {
                    Circle().fill(isRotationPaused ? Color.orange : Color.green).frame(width: 8, height: 8)
                    Text(isRotationPaused ? "Desktop Rotation Paused:" : "Live Desktop Rotation:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(isRotationPaused ? .orange : .green)
                    Text(scope == .entireCollection ? "Entire \(displayName)" : "My \(displayName)")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: {
                        NotificationCenter.default.post(name: .didRequestNextWallpaper, object: nil)
                    }) {
                        Label("Next Wallpaper", systemImage: "forward.end.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.08))
            }

            Divider()

            // Collections Grid
            ScrollView {
                let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredCollections) { col in
                        let isMyRotating: Bool = {
                            if case .collection(let activeContract, _, let scope) = activeRotationTarget {
                                return activeContract.caseInsensitiveCompare(col.contract) == .orderedSame && scope == .inLibrary
                            }
                            return false
                        }()
                        let isEntireRotating: Bool = {
                            if case .collection(let activeContract, _, let scope) = activeRotationTarget {
                                return activeContract.caseInsensitiveCompare(col.contract) == .orderedSame && scope == .entireCollection
                            }
                            return false
                        }()

                        CollectionCardView(
                            item: col,
                            previewTokens: tokens.filter { collectionTokenMatches(token: $0, key: col.contract) }.prefix(4),
                            isRotating: isMyRotating || isEntireRotating,
                            isMyRotating: isMyRotating,
                            isEntireRotating: isEntireRotating,
                            onSelect: {
                                selectedSidebarItem = .collection(col.contract)
                            },
                            onStartRotatingMy: {
                                startRotatingCurrentScope(.collection(contract: col.contract, displayName: col.displayName, scope: .inLibrary))
                            },
                            onStartRotatingEntire: {
                                loadEntireCollection(for: col.contract)
                                startRotatingCurrentScope(.collection(contract: col.contract, displayName: col.displayName, scope: .entireCollection))
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Collections (\(filteredCollections.count))")
    }

    private var filteredCollections: [CollectionContractItem] {
        if collectionSearchText.isEmpty {
            return cachedUniqueCollections
        }
        return cachedUniqueCollections.filter {
            $0.displayName.localizedCaseInsensitiveContains(collectionSearchText) ||
            $0.contract.localizedCaseInsensitiveContains(collectionSearchText)
        }
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 8) {
            // Scope Artworks Count
            Text("\(displayedTokens.count) Artworks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .fixedSize()

            // Active Collection Filter Chip (if filtered inside scope)
            if let activeContract = selectedContractFilter {
                HStack(spacing: 4) {
                    Text(resolvedName(for: activeContract))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Button(action: { selectedContractFilter = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(4)
            }

            Spacer(minLength: 8)

            // Format Filter Dropdown
            Menu {
                ForEach(FormatFilter.allCases) { filter in
                    Button(action: { selectedFormatFilter = filter }) {
                        if selectedFormatFilter == filter {
                            Label(filter.rawValue, systemImage: "checkmark")
                        } else {
                            Text(filter.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedFormatFilter == .all ? "Format" : selectedFormatFilter.rawValue)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10))
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Sort Menu (combines sort field & direction)
            Menu {
                ForEach(TokenSortOption.allCases) { opt in
                    Button(action: { sortOption = opt }) {
                        if sortOption == opt {
                            Label(opt.rawValue, systemImage: "checkmark")
                        } else {
                            Text(opt.rawValue)
                        }
                    }
                }
                Divider()
                Button(action: { sortDirection = .ascending }) {
                    if sortDirection == .ascending {
                        Label("Ascending", systemImage: "checkmark")
                    } else {
                        Text("Ascending")
                    }
                }
                Button(action: { sortDirection = .descending }) {
                    if sortDirection == .descending {
                        Label("Descending", systemImage: "checkmark")
                    } else {
                        Text("Descending")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: sortDirection.iconName)
                    Text(sortOption.rawValue)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10))
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Asc / Desc quick toggle button
            Button(action: {
                sortDirection = (sortDirection == .ascending) ? .descending : .ascending
            }) {
                Image(systemName: sortDirection == .ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .padding(4)
                    .background(Color.secondary.opacity(0.10))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help(sortDirection == .ascending ? "Ascending (Click for Descending)" : "Descending (Click for Ascending)")

            // Grid Size Slider
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Slider(value: $gridSize, in: 130...280)
                    .frame(width: 60)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            // Sync Button
            Button(action: {
                Task { await syncAllSources() }
            }) {
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)
            .help("Sync sources and curations")
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(.ultraThinMaterial)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Art Tokens Found")
                .font(.headline)
            Text(emptyStateExplanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Manage Sources…") {
                isSourceSheetPresented = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    private var emptyStateExplanation: String {
        if !searchText.isEmpty {
            return "No tokens match '\(searchText)'. Try adjusting your search query or filters."
        }
        if case .created = selectedSidebarItem {
            return "No created artworks found for this wallet. Sync sources to fetch your minted pieces from objkt."
        }
        if case .customGallery = selectedSidebarItem {
            return "This desKTop Gallery is empty. Right-click any token in the gallery to add it here."
        }
        return "Connect your Tezos wallet or .tez domain in Sources to index your art collection."
    }

    private var navigationTitleString: String {
        switch selectedSidebarItem {
        case .allArt: return "All Art (\(displayedTokens.count))"
        case .owned: return "Owned Art (\(displayedTokens.count))"
        case .created: return "Created Art (\(displayedTokens.count))"
        case .collections: return "Collections (\(filteredCollections.count))"
        case .customGallery(let gid):
            let name = galleries.first(where: { $0.id == gid })?.name ?? "Gallery"
            return "\(name) (\(displayedTokens.count))"
        case .objktCuration(let cid):
            let name = objktCurations.first(where: { $0.galleryId == cid })?.name ?? "Curation"
            return "\(name) (\(displayedTokens.count))"
        case .collection(let contract):
            let displayName = resolvedName(for: contract)
            return "\(displayName) (\(displayedTokens.count))"
        case .source(let sid):
            let srcName = sources.first(where: { $0.id == sid })?.displayName ?? "Source"
            let scopeLabel = (sourceScope == .created) ? "Created" : "Owned"
            return "\(srcName) (\(scopeLabel) • \(displayedTokens.count))"
        }
    }

    private var inspectorPlaceholderView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Select an artwork to inspect details")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("Right-click any artwork to set wallpaper, filter by collection, or add to a desKTop gallery")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newGallerySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New desKTop Gallery")
                    .font(.headline)
                Spacer()
                if newGalleryType == .smart {
                    Text("SMART PLAYLIST")
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.18))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }
            }

            // Mode Selector: Smart Rule-Based vs Curated Hand-Picked
            if newGalleryCriteria != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gallery Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Gallery Mode", selection: $newGalleryType) {
                        Text("Smart Gallery (Dynamic Rules)").tag(GalleryType.smart)
                        Text("Curated Gallery (Hand-Picked)").tag(GalleryType.manual)
                    }
                    .pickerStyle(.segmented)

                    if newGalleryType == .smart {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 11))
                                    .foregroundColor(.purple)
                                Text("Dynamic Rule Criteria")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.purple)
                            }
                            if let q = newGalleryCriteria?.searchText, !q.isEmpty {
                                Text("• Search query: \"\(q)\"").font(.caption2).foregroundColor(.secondary)
                            }
                            if let f = newGalleryCriteria?.formatFilter, !f.isEmpty {
                                Text("• Format filter: \(f)").font(.caption2).foregroundColor(.secondary)
                            }
                            if let c = newGalleryCriteria?.collectionKey, !c.isEmpty {
                                Text("• Collection: \(resolvedName(for: c))").font(.caption2).foregroundColor(.secondary)
                            }
                            if let s = newGalleryCriteria?.sourceScope, !s.isEmpty {
                                Text("• Scope: \(s.capitalized)").font(.caption2).foregroundColor(.secondary)
                            }
                            Text("Automatically includes matching pieces now and on all future library syncs.")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(.top, 2)
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(6)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Pins the \(tokensToAddToNewGallery.count) artworks currently visible. You can add or remove pieces by hand.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(6)
                    }
                }
            } else {
                // When created fresh from sidebar '+'
                VStack(alignment: .leading, spacing: 6) {
                    Text("Creation Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Creation Mode", selection: $newGalleryCreationMode) {
                        Text("Hand-Curated Playlist").tag("curated")
                        Text("Follow a Wallet or Artist").tag("wallet")
                    }
                    .pickerStyle(.segmented)

                    if newGalleryCreationMode == "wallet" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                    .foregroundColor(.purple)
                                Text("Follow Wallet / Artist as Smart Gallery")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.purple)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tezos Wallet Address or .tez Domain")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("e.g. artist.tez or tz1...", text: $newGalleryTargetWallet)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Picker("Works to Include", selection: $newGalleryTargetWalletScope) {
                                Text("Created Works").tag(WalletFollowScope.created)
                                Text("Owned Holdings").tag(WalletFollowScope.owned)
                            }
                            .pickerStyle(.segmented)

                            Text("Automatically indexes on-chain pieces from Objkt & TzKT.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Gallery Name (Optional if Following Wallet)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Late Night Vibes, Generative Favorites…", text: $newGalleryName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Optional description for this playlist…", text: $newGalleryDesc)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isNewGallerySheetPresented = false
                }
                .keyboardShortcut(.cancelAction)

                if isCreatingSmartFollower {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(newGalleryCreationMode == "wallet" && newGalleryCriteria == nil ? "Follow as Smart Gallery" : "Create Gallery") {
                    let name = newGalleryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let walletInput = newGalleryTargetWallet.trimmingCharacters(in: .whitespacesAndNewlines)

                    if newGalleryCreationMode == "wallet" && newGalleryCriteria == nil {
                        guard !walletInput.isEmpty else { return }
                        isCreatingSmartFollower = true
                        Task {
                            let g: DesktopGallery?
                            let finalName = name.isEmpty ? (newGalleryTargetWalletScope == .created ? "Created by \(walletInput)" : "Collected by \(walletInput)") : name
                            if newGalleryTargetWalletScope == .created {
                                g = try? await repository.followCreator(addressOrDomain: walletInput, displayName: finalName)
                            } else {
                                g = try? await repository.followCollector(addressOrDomain: walletInput, displayName: finalName)
                            }
                            isCreatingSmartFollower = false
                            await reloadData()
                            if let g = g {
                                selectedSidebarItem = .customGallery(g.id)
                            }
                            newGalleryTargetWallet = ""
                            isNewGallerySheetPresented = false
                        }
                    } else {
                        guard !name.isEmpty else { return }
                        Task {
                            if newGalleryType == .smart, let crit = newGalleryCriteria {
                                _ = try? await repository.createSmartGallery(
                                    name: name,
                                    description: newGalleryDesc.isEmpty ? nil : newGalleryDesc,
                                    criteria: crit
                                )
                            } else {
                                _ = try? await repository.createManualGallery(
                                    name: name,
                                    description: newGalleryDesc.isEmpty ? nil : newGalleryDesc,
                                    tokenIds: tokensToAddToNewGallery
                                )
                            }
                            tokensToAddToNewGallery = []
                            newGalleryCriteria = nil
                            await reloadData()
                            isNewGallerySheetPresented = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    (newGalleryCreationMode == "wallet" && newGalleryCriteria == nil) ?
                        newGalleryTargetWallet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty :
                        newGalleryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Data Synchronization

    private func reloadData(skipNetworkResolve: Bool = false) async {
        self.sources = await repository.getSources()
        self.tokens = await repository.getTokens()
        self.galleries = await repository.getGalleries()
        self.objktCurations = await repository.getObjktCurations()
        self.activeRotationTarget = await repository.getActiveRotationTarget()
        self.isRotationPaused = await repository.isRotationPaused()
        self.isRotationShuffle = await repository.isRotationShuffle()
        let intervalSec = await repository.getRotationInterval()
        self.rotationInterval = RotationInterval(rawValue: intervalSec) ?? .fiveMinutes

        if !hasLoadedDiskCaches {
            hasLoadedDiskCaches = true
            let colSnapshot = await CollectionResolver.shared.cachedNamesSnapshot()
            let (profiles, fxhash) = await Task.detached(priority: .userInitiated) {
                (ArtistResolver.loadCachedProfiles(), FxhashResolver.loadCachedProjects())
            }.value
            self.collectionNames.merge(colSnapshot) { _, new in new }
            self.artistProfiles.merge(profiles) { _, new in new }
            self.fxhashProjects.merge(fxhash) { _, new in new }
        }

        updateDisplayedTokens()
        recomputeDerivedStats()

        if !skipNetworkResolve {
            scheduleBackgroundMetadataResolution()
        }
    }

    private func scheduleBackgroundMetadataResolution() {
        backgroundResolveTask?.cancel()
        let snapTokens = tokens
        guard !snapTokens.isEmpty else { return }

        backgroundResolveTask = Task.detached(priority: .utility) {
            // Yield briefly so UI layout and visible disk thumbnails render without contention
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }

            let contracts = Array(Set(snapTokens.map { $0.contract }))
            let creators = Array(Set(snapTokens.flatMap(\.creators)))
            let fxTokens = snapTokens.filter { $0.isFxhash }

            async let fetchedCols = CollectionResolver.shared.resolveNames(for: contracts)
            async let fetchedArtists = ArtistResolver.shared.resolveArtists(for: creators)
            async let fetchedFx = FxhashResolver.shared.resolveProjects(for: fxTokens)

            let (names, resolvedArtists, resolvedFx) = await (fetchedCols, fetchedArtists, fetchedFx)
            if Task.isCancelled { return }

            await MainActor.run {
                var needsDerivedRefresh = false
                if !names.isEmpty {
                    self.collectionNames.merge(names) { _, new in new }
                    needsDerivedRefresh = true
                }
                if !resolvedArtists.isEmpty {
                    self.artistProfiles.merge(resolvedArtists) { _, new in new }
                    needsDerivedRefresh = true
                }
                if !resolvedFx.isEmpty {
                    self.fxhashProjects.merge(resolvedFx) { _, new in new }
                    needsDerivedRefresh = true
                }
                if needsDerivedRefresh {
                    self.recomputeDerivedStats()
                }
            }
        }
    }

    private func loadEntireCollection(for key: String) {
        Task {
            if let cached = await repository.getFullCollectionTokens(key: key), !cached.isEmpty {
                await MainActor.run {
                    self.entireCollectionTokens[key] = cached
                    self.updateDisplayedTokens()
                }
                return
            }

            await MainActor.run {
                self.isFetchingEntireCollection = true
            }

            let client = ObjktClient()
            if let fetched = try? await client.fetchEntireCollection(key: key) {
                let libraryOwnedIds = Set(tokens.filter { $0.isOwned }.map(\.id))
                let sourceAddresses = Set(sources.compactMap { $0.walletAddress?.lowercased() })

                let annotated = fetched.map { t -> UnifiedToken in
                    var copy = t
                    if libraryOwnedIds.contains(t.id) {
                        copy.isOwned = true
                    }
                    if copy.creators.contains(where: { sourceAddresses.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) {
                        copy.isCreated = true
                    }
                    return copy
                }

                try? await repository.setFullCollectionTokens(key: key, tokens: annotated)

                await MainActor.run {
                    self.entireCollectionTokens[key] = annotated
                    self.isFetchingEntireCollection = false
                }
            } else {
                await MainActor.run {
                    self.isFetchingEntireCollection = false
                }
            }
        }
    }

    private func syncAllSources() async {
        isSyncing = true
        defer { isSyncing = false }

        let tzkt = TzKTClient()
        let filter = FungibleFilterEngine()
        let objkt = ObjktClient()

        for source in sources {
            switch source.type {
            case .wallet(let address, _):
                // 1. Fetch owned tokens from TzKT
                if let owned = try? await tzkt.fetchAllTokens(for: address) {
                    let artTokens = filter.filter(owned).map { token -> UnifiedToken in
                        var t = token
                        t.isOwned = true
                        return t
                    }
                    var updated = source
                    updated.tokenCount = artTokens.count
                    try? await repository.updateSource(updated)
                    try? await repository.upsertTokens(artTokens)
                }

                // 2. Fetch created art tokens from objkt GraphQL (paginated up to 1000)
                if let created = try? await objkt.fetchCreatedTokens(creator: address, limit: 1000) {
                    let artCreated = filter.filter(created)
                    try? await repository.upsertTokens(artCreated)
                }

                // 3. Fetch objkt curations for this wallet
                if let curations = try? await objkt.fetchUserGalleries(curator: address) {
                    try? await repository.setObjktCurations(curations)

                    for cur in curations {
                        if let cTokens = try? await objkt.fetchCurationTokens(slugOrId: cur.galleryId, limit: 100) {
                            let tagged = cTokens.map { t -> UnifiedToken in
                                var meta = t.rawMetadata ?? [:]
                                meta["curationId"] = cur.galleryId
                                return UnifiedToken(
                                    contract: t.contract,
                                    tokenId: t.tokenId,
                                    name: t.name,
                                    description: t.description,
                                    creators: t.creators,
                                    mimeType: t.mimeType,
                                    artifactUri: t.artifactUri,
                                    displayUri: t.displayUri,
                                    thumbnailUri: t.thumbnailUri,
                                    formats: t.formats,
                                    attributes: t.attributes,
                                    supply: t.supply,
                                    decimals: t.decimals,
                                    aleatory: t.aleatory,
                                    rawMetadata: meta,
                                    isOwned: t.isOwned,
                                    isCreated: t.isCreated
                                )
                            }
                            try? await repository.upsertTokens(tagged)
                        }
                    }
                }

            case .collection(let contract, _):
                if let tokens = try? await tzkt.fetchContractTokens(contract: contract, limit: 500) {
                    let artTokens = filter.filter(tokens)
                    var updated = source
                    updated.tokenCount = artTokens.count
                    try? await repository.updateSource(updated)
                    try? await repository.upsertTokens(artTokens)
                }

            case .objktCuration(let id, _):
                if let tokens = try? await objkt.fetchCurationTokens(slugOrId: id, limit: 500) {
                    let artTokens = filter.filter(tokens)
                    var updated = source
                    updated.tokenCount = artTokens.count
                    try? await repository.updateSource(updated)
                    try? await repository.upsertTokens(artTokens)
                }
            }
        }

        await reloadData()
    }
}

// MARK: - Collection Card View (For Collections Browser)

struct CollectionCardView: View {
    let item: CollectionContractItem
    let previewTokens: ArraySlice<UnifiedToken>
    let isRotating: Bool
    let isMyRotating: Bool
    let isEntireRotating: Bool
    let onSelect: () -> Void
    let onStartRotatingMy: () -> Void
    let onStartRotatingEntire: () -> Void

    @State private var isHovered: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preview Image Grid (up to 4 thumbnails)
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.12)

                if previewTokens.isEmpty {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                } else if previewTokens.count == 1, let first = previewTokens.first {
                    ArtworkThumbnailView(token: first, contentMode: .fill)
                        .clipped()
                } else {
                    let gridTokens = Array(previewTokens.prefix(4))
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            if gridTokens.indices.contains(0) {
                                ArtworkThumbnailView(token: gridTokens[0], contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Color.secondary.opacity(0.08)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            if gridTokens.indices.contains(1) {
                                ArtworkThumbnailView(token: gridTokens[1], contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Color.secondary.opacity(0.08)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        HStack(spacing: 2) {
                            if gridTokens.indices.contains(2) {
                                ArtworkThumbnailView(token: gridTokens[2], contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Color.secondary.opacity(0.08)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            if gridTokens.indices.contains(3) {
                                ArtworkThumbnailView(token: gridTokens[3], contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Color.secondary.opacity(0.08)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                // Rotating badge on preview
                if isRotating {
                    Text(isEntireRotating ? "ENTIRE LIVE" : "MY PIECES LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green)
                        .cornerRadius(4)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .frame(height: 140)
            .clipped()
            .cornerRadius(8)

            // Collection Details
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack {
                    Text("\(item.count) in library")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(item.shortContract)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 4)

            // Dual 1-Click Action Buttons: Rotate My vs Rotate Entire
            HStack(spacing: 6) {
                Button(action: onStartRotatingMy) {
                    HStack(spacing: 3) {
                        Image(systemName: isMyRotating ? "checkmark.circle.fill" : "play.fill")
                            .font(.system(size: 9))
                        Text(isMyRotating ? "Rotating My" : "Rotate My (\(item.count))")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isMyRotating ? Color.green : Color.accentColor)
                .controlSize(.small)

                Button(action: onStartRotatingEntire) {
                    HStack(spacing: 3) {
                        Image(systemName: isEntireRotating ? "checkmark.circle.fill" : "globe")
                            .font(.system(size: 9))
                        Text(isEntireRotating ? "Rotating All" : "Rotate Entire")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .tint(isEntireRotating ? Color.green : Color.secondary)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(isHovered ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isRotating ? Color.green.opacity(0.5) : (isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15)), lineWidth: isRotating ? 2 : 1)
        )
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if !Task.isCancelled {
                        isHovered = true
                    }
                }
            } else {
                isHovered = false
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button(action: onSelect) {
                Label("Browse Collection…", systemImage: "rectangle.stack")
            }
            Divider()
            Button(action: onStartRotatingMy) {
                Label("Rotate My Pieces on Desktop (\(item.count))", systemImage: "play.circle")
            }
            Button(action: onStartRotatingEntire) {
                Label("Rotate Entire Collection on Desktop (on-chain)", systemImage: "globe")
            }
        }
    }
}

// MARK: - Artwork Card View

struct TokenCardView: View {
    let token: UnifiedToken
    let collectionName: String
    let artistName: String
    let isSelected: Bool
    let isLiveOnDesktop: Bool
    let isApplyingToDesktop: Bool
    let galleries: [DesktopGallery]
    let onSelect: () -> Void
    let onSetAsWallpaper: () -> Void
    let onAddToGallery: (UUID) -> Void
    let onFilterByCollection: (String) -> Void
    let onRemoveFromCurrentGallery: () -> Void

    @State private var isHovered: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Artwork Image Box (Strictly bounded geometry so GIFs or WebViews can never overflow)
            GeometryReader { geo in
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.15)

                    ArtworkThumbnailView(token: token, contentMode: .fill, isHovered: isHovered)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // Top Left Live / Applying / Ownership Badges
                    VStack {
                        HStack(spacing: 4) {
                            if isApplyingToDesktop {
                                HStack(spacing: 3) {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .scaleEffect(0.65)
                                    Text("APPLYING…")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange)
                                .cornerRadius(4)
                                .shadow(radius: 2)
                            } else if isLiveOnDesktop {
                                Text("LIVE ON DESKTOP")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                                    .shadow(radius: 2)
                            }
                            if token.isOwned {
                                Text("OWNED")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.green)
                                    .cornerRadius(4)
                                    .shadow(radius: 2)
                            } else if token.isCreated {
                                Text("CREATED")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.purple)
                                    .cornerRadius(4)
                                    .shadow(radius: 2)
                            }
                            Spacer()
                        }
                        .padding(6)
                        Spacer()
                    }

                    // Bottom Right Category Badge
                    Text(token.mediaCategory.displayName)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                        .padding(6)

                    // Quick Set Hover Action Overlay
                    if isHovered {
                        VStack {
                            Spacer()
                            HStack {
                                Button(action: onSetAsWallpaper) {
                                    Label("Set Desktop", systemImage: "display")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .shadow(radius: 4)

                                Spacer()
                            }
                            .padding(8)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Metadata info & collection link
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(token.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if !token.name.contains("#") {
                        Text("#\(token.tokenId)")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }

                if !artistName.isEmpty {
                    Text("by \(artistName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Clickable collection pill
                Button(action: {
                    onFilterByCollection(token.contract)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(collectionName)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Filter library to \(collectionName)")
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if !Task.isCancelled {
                        isHovered = true
                    }
                }
            } else {
                isHovered = false
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button(action: onSetAsWallpaper) {
                Label("Set as macOS Wallpaper", systemImage: "display")
            }

            Button(action: {
                onFilterByCollection(token.contract)
            }) {
                Label("Show All in '\(collectionName)'", systemImage: "rectangle.stack")
            }

            Divider()

            if !galleries.isEmpty {
                Menu("Add to desKTop Gallery") {
                    ForEach(galleries) { g in
                        Button(g.name) {
                            onAddToGallery(g.id)
                        }
                    }
                }
            }

            Button(action: onRemoveFromCurrentGallery) {
                Label("Remove from Gallery", systemImage: "minus.circle")
            }

            Divider()

            Button("View Token on objkt.com") {
                if let url = URL(string: "https://objkt.com/tokens/\(token.contract)/\(token.tokenId)") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("View Collection on objkt.com") {
                if let url = URL(string: "https://objkt.com/collections/\(token.contract)") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Copy Token Contract & ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(token.id, forType: .string)
            }
        }
    }
}

// MARK: - In-Memory Image Cache

final class ImageMemoryCache: @unchecked Sendable {
    nonisolated(unsafe) static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 64 * 1024 * 1024 // 64MB limit to keep memory minimal
        return cache
    }()
}

// MARK: - Native Animated GIF Player View

final class NonExpandingImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 100, height: 100)
    }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.masksToBounds = true
    }
}

public struct AppKitGIFRepresentable: NSViewRepresentable {
    let image: NSImage
    let contentMode: ContentMode

    public func makeNSView(context: Context) -> NSImageView {
        let view = NonExpandingImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        let w = proposal.width ?? 160
        let h = proposal.height ?? 160
        return CGSize(width: w, height: h)
    }

    public func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
        }
        if !nsView.animates {
            nsView.animates = true
        }
    }
}

public struct AnimatedGIFView: View {
    let url: URL?
    let contentMode: ContentMode
    let animates: Bool

    @State private var image: NSImage?
    @State private var isLoading: Bool = false
    @State private var hasFailed: Bool = false

    public init(url: URL?, contentMode: ContentMode = .fill, animates: Bool = false) {
        self.url = url
        self.contentMode = contentMode
        self.animates = animates
    }

    public var body: some View {
        ZStack {
            if let image = image {
                if animates {
                    AppKitGIFRepresentable(image: image, contentMode: contentMode)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else if isLoading {
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView()
                        .controlSize(.small)
                }
            } else if hasFailed {
                ZStack {
                    Color.secondary.opacity(0.12)
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                        Text("GIF")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Color.secondary.opacity(0.08)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else {
            hasFailed = true
            return
        }

        isLoading = true
        hasFailed = false

        if let img = await ThumbnailPipeline.shared.loadAnimatedGIF(for: url) {
            self.image = img
            self.isLoading = false
        } else {
            self.hasFailed = true
            self.isLoading = false
        }
    }
}

// MARK: - Fast Off-Thread Cached Thumbnail Loader

public struct CachedThumbnailImageView: View {
    let url: URL
    let fallbackURL: URL?
    let contentMode: ContentMode
    let placeholder: AnyView

    @State private var loadedImage: NSImage?
    @State private var isLoading: Bool = false
    @State private var hasFailed: Bool = false

    public init<P: View>(url: URL, fallbackURL: URL? = nil, contentMode: ContentMode = .fill, placeholder: P) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.contentMode = contentMode
        self.placeholder = AnyView(placeholder)
        let preloaded = ImageMemoryCache.shared.object(forKey: url as NSURL)
            ?? fallbackURL.flatMap { ImageMemoryCache.shared.object(forKey: $0 as NSURL) }
        self._loadedImage = State(initialValue: preloaded)
    }

    public var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipped()
            } else if isLoading {
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView()
                        .controlSize(.small)
                }
            } else if hasFailed {
                placeholder
            } else {
                Color.secondary.opacity(0.08)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let nsURL = url as NSURL
        if let cached = ImageMemoryCache.shared.object(forKey: nsURL) {
            self.loadedImage = cached
            return
        }

        isLoading = true
        hasFailed = false

        if let img = await ThumbnailPipeline.shared.loadThumbnail(for: url, maxPixelSize: 360) {
            self.loadedImage = img
            self.isLoading = false
        } else if let fb = fallbackURL,
                  let fbImg = await ThumbnailPipeline.shared.loadThumbnail(for: fb, maxPixelSize: 360) {
            self.loadedImage = fbImg
            self.isLoading = false
        } else {
            self.hasFailed = true
            self.isLoading = false
        }
    }
}

// MARK: - Artwork Thumbnail Loader

public struct ArtworkThumbnailView: View {
    let token: UnifiedToken
    let contentMode: ContentMode
    var isHovered: Bool = false
    var shouldAnimate: Bool = false

    public init(token: UnifiedToken, contentMode: ContentMode = .fill, isHovered: Bool = false, shouldAnimate: Bool = false) {
        self.token = token
        self.contentMode = contentMode
        self.isHovered = isHovered
        self.shouldAnimate = shouldAnimate
    }

    private var targetURL: URL? {
        guard let uri = token.preferredThumbnailUri else { return nil }
        return IPFSGatewayManager.resolvePublicURL(for: uri)
    }

    private var fallbackURL: URL? {
        guard let disp = token.displayUri,
              disp != token.preferredThumbnailUri,
              UnifiedToken.isVisualUri(disp) else {
            return nil
        }
        return IPFSGatewayManager.resolvePublicURL(for: disp)
    }

    public var body: some View {
        if token.mediaCategory == .animatedImage, (shouldAnimate || isHovered), let url = targetURL {
            AnimatedGIFView(url: url, contentMode: contentMode, animates: true)
                .clipped()
        } else if let url = targetURL {
            CachedThumbnailImageView(url: url, fallbackURL: fallbackURL, contentMode: contentMode, placeholder: placeholderView)
                .clipped()
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: iconName(for: token.mediaCategory))
                .font(.system(size: 26))
                .foregroundColor(.secondary)
        }
    }

    private func iconName(for category: MediaCategory) -> String {
        switch category {
        case .staticImage, .vectorImage: return "photo"
        case .animatedImage: return "sparkles"
        case .video: return "video"
        case .interactiveHtml, .fxhash, .editArt: return "chevron.left.forwardslash.chevron.right"
        case .aleatory: return "dice"
        case .bootloader: return "cpu"
        case .audio3d: return "cube"
        case .unknown: return "photo.on.rectangle.angled"
        }
    }
}

// MARK: - Token Inspector View

struct TokenInspectorView: View {
    let token: UnifiedToken
    let collectionName: String
    let collectionTokensCount: Int
    let artistProfile: ArtistProfile?
    let artistDisplayName: String
    let fxhashProjectInfo: FxhashProjectInfo?
    let isLiveOnDesktop: Bool
    let isApplyingToDesktop: Bool
    let desktopPhase: DesktopWallpaperState.Phase
    let isCollectionMyRotating: Bool
    let isCollectionEntireRotating: Bool
    let galleries: [DesktopGallery]
    @Binding var matteMode: WallpaperMatteMode
    @Binding var customHex: String
    let onSetWallpaper: () -> Void
    let onRotateCollectionMy: () -> Void
    let onRotateCollectionEntire: () -> Void
    let onAddToGallery: (UUID) -> Void
    let onFilterByCollection: (String) -> Void
    let onFollowArtistCreated: (String, String) -> Void
    let onFollowArtistOwned: (String, String) -> Void

    private var formattedMintDate: String? {
        guard let dateStr = token.rawMetadata?["date"], !dateStr.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateStr) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        let fallbackIso = ISO8601DateFormatter()
        if let date = fallbackIso.date(from: dateStr) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        if dateStr.count >= 10 {
            return String(dateStr.prefix(10))
        }
        return dateStr
    }

    private var editionText: String? {
        if let supply = token.supply {
            if supply == 1 {
                return "1/1 (Unique)"
            }
            return "\(supply) editions"
        }
        return nil
    }

    private var rightsText: String? {
        if let rights = token.rawMetadata?["rights"], !rights.isEmpty {
            return rights
        }
        return nil
    }

    private var mintingToolText: String? {
        if let tool = token.rawMetadata?["mintingTool"], !tool.isEmpty {
            return tool.replacingOccurrences(of: "https://", with: "")
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Large Preview
                ArtworkThumbnailView(token: token, contentMode: .fit, shouldAnimate: true)
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(8)

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text(token.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    if token.isFxhash {
                        HStack(spacing: 6) {
                            if let version = token.fxhashVersion {
                                Text("fxhash \(version)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }
                            if let iter = fxhashProjectInfo?.iteration ?? token.fxhashIteration {
                                Text("Iteration #\(iter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let pId = fxhashProjectInfo?.issuerId ?? token.fxhashProjectId {
                                Text("Project #\(pId)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                        }
                    }
                }

                // Verified Artist Identity Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Text(String(artistDisplayName.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(artistDisplayName)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                if artistProfile?.alias != nil || artistProfile?.tzdomain != nil {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                            }

                            if let tzdomain = artistProfile?.tzdomain {
                                Text(tzdomain)
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            } else if let addr = token.creators.first {
                                Text(String(addr.prefix(6)) + "…" + String(addr.suffix(4)))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }

                    // Social & Profile Links
                    HStack(spacing: 6) {
                        if let twitterHandle = artistProfile?.twitterHandle, let twitterURL = artistProfile?.twitterURL {
                            Button(action: { NSWorkspace.shared.open(twitterURL) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.system(size: 9))
                                    Text(twitterHandle)
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.10))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }

                        if let websiteURL = artistProfile?.websiteURL {
                            Button(action: { NSWorkspace.shared.open(websiteURL) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 9))
                                    Text("Website")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.10))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }

                        if let objktURL = artistProfile?.objktProfileURL {
                            Button(action: { NSWorkspace.shared.open(objktURL) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 9))
                                    Text("objkt")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.10))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }

                        if let tzktURL = artistProfile?.tzktProfileURL {
                            Button(action: { NSWorkspace.shared.open(tzktURL) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 9))
                                    Text("TzKT")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.10))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let desc = artistProfile?.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(desc.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .padding(8)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(6)
                    }

                    // 1-Click Follow Artist Smart Gallery Actions
                    if let creatorAddr = artistProfile?.address ?? token.creators.first {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FOLLOW ARTIST")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.secondary)

                            HStack(spacing: 6) {
                                Button(action: {
                                    onFollowArtistCreated(creatorAddr, artistDisplayName)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "wand.and.stars")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Follow Created Works")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundColor(.purple)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Create a Smart Gallery tracking all works created by \(artistDisplayName)")

                                Button(action: {
                                    onFollowArtistOwned(creatorAddr, artistDisplayName)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.crop.rectangle.stack")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Follow Collected")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.10))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Create a Smart Gallery tracking all works collected by \(artistDisplayName)")
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)

                // Collection & 1-Click Desktop Rotation
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: token.isFxhash ? "sparkles.rectangle.stack.fill" : "folder.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collectionName)
                                .font(.headline)
                                .lineLimit(1)
                            if token.isFxhash, let v = token.fxhashVersion {
                                Text("fxhash Generative Project • \(v)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(collectionTokensCount) artworks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 6) {
                        Button(action: onRotateCollectionEntire) {
                            HStack(spacing: 6) {
                                Image(systemName: isCollectionEntireRotating ? "checkmark.circle.fill" : "globe")
                                Text(isCollectionEntireRotating ? "Rotating Entire Collection" : (token.isFxhash ? "Rotate Entire Project on Desktop" : "Rotate Entire Collection on Desktop"))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isCollectionEntireRotating ? Color.green : Color.accentColor)
                        .controlSize(.regular)

                        if collectionTokensCount > 0 {
                            Button(action: onRotateCollectionMy) {
                                HStack(spacing: 6) {
                                    Image(systemName: isCollectionMyRotating ? "checkmark.circle.fill" : "person.fill")
                                    Text(isCollectionMyRotating ? "Rotating My Pieces on Desktop" : "Rotate My Pieces (\(collectionTokensCount))")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(isCollectionMyRotating ? Color.green : Color.secondary)
                            .controlSize(.regular)
                        }
                    }

                    Button(action: {
                        let filterKey = token.isFxhash ? "fxhash:\(collectionName)" : token.contract
                        onFilterByCollection(filterKey)
                    }) {
                        HStack(spacing: 4) {
                            Text(token.isFxhash ? "Browse all \(collectionTokensCount) project pieces" : "Browse all \(collectionTokensCount) artworks")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)

                // Primary Set Desktop Action
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: onSetWallpaper) {
                        if isApplyingToDesktop {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                if case .loading(_, let msg) = desktopPhase {
                                    Text(msg)
                                } else {
                                    Text("Applying to Desktop…")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else if isLiveOnDesktop {
                            Label("Live on Desktop", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Set as Desktop Wallpaper", systemImage: "display")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isApplyingToDesktop ? .orange : (isLiveOnDesktop ? .green : .accentColor))
                    .disabled(isApplyingToDesktop)
                    .controlSize(.large)

                    if case .failed(let failedId, let errMsg) = desktopPhase, failedId == token.id {
                        Text("Failed to apply: \(errMsg)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }

                // Add to Gallery Picker
                if !galleries.isEmpty {
                    Menu {
                        ForEach(galleries) { g in
                            Button(g.name) {
                                onAddToGallery(g.id)
                            }
                        }
                    } label: {
                        Label("Add to desKTop Gallery…", systemImage: "plus.rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                }

                // Desktop Matte & Letterbox Background Selector
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Wallpaper Matte & Letterbox")
                            .font(.headline)
                        Spacer()
                        Circle()
                            .fill(Color(nsColor: ArtworkMatteEngine.resolveMatteColor(imageURL: nil, mode: matteMode, customHex: customHex)))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    }

                    Picker("Matte Style", selection: $matteMode) {
                        ForEach(WallpaperMatteMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if matteMode == .custom {
                        HStack {
                            Text("Hex Color:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("#000000", text: $customHex)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    } else if matteMode == .dynamicArtwork {
                        Text("Auto-extracts dominant color from the artwork to blend letterbox borders.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Direct Marketplace Links
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Marketplace & Explorer")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    if token.isFxhash {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            if let url = token.objktTokenURL {
                                Button(action: { NSWorkspace.shared.open(url) }) {
                                    Label("Token on objkt", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                                .buttonStyle(.link)
                            }
                            if let url = token.fxhashGentkURL {
                                Button(action: { NSWorkspace.shared.open(url) }) {
                                    Label("Gentk on fxhash", systemImage: "sparkles")
                                        .font(.caption)
                                }
                                .buttonStyle(.link)
                            }
                            if let pId = fxhashProjectInfo?.issuerId ?? token.fxhashProjectId,
                               let url = token.objktCollectionURL(projectId: pId) {
                                Button(action: { NSWorkspace.shared.open(url) }) {
                                    Label("Project on objkt", systemImage: "folder")
                                        .font(.caption)
                                }
                                .buttonStyle(.link)
                            }
                            if let pId = fxhashProjectInfo?.issuerId ?? token.fxhashProjectId,
                               let url = token.fxhashProjectURL(projectId: pId) {
                                Button(action: { NSWorkspace.shared.open(url) }) {
                                    Label("Project on fxhash", systemImage: "cube")
                                        .font(.caption)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button(action: {
                                if let url = token.objktTokenURL {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                Label("Token on objkt", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            .buttonStyle(.link)

                            Button(action: {
                                if let url = token.objktCollectionURL() {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                Label("Collection on objkt", systemImage: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                if let desc = token.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.headline)
                        Text(desc.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Artwork Provenance")
                        .font(.headline)

                    if let ed = editionText {
                        DetailRow(label: "Editions / Supply", value: ed)
                    }
                    if let mintDate = formattedMintDate {
                        DetailRow(label: "Mint Date", value: mintDate)
                    }
                    if let tool = mintingToolText {
                        DetailRow(label: "Minting Tool", value: tool)
                    }
                    if let rights = rightsText {
                        DetailRow(label: "Rights / License", value: rights)
                    }
                    DetailRow(label: "Format Category", value: token.mediaCategory.displayName)
                    if let mime = token.mimeType {
                        DetailRow(label: "MIME Type", value: mime)
                    }
                    DetailRow(label: "Token ID", value: "#\(token.tokenId)")
                    DetailRow(label: "Collection Contract", value: token.contract)
                }

                if !token.attributes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attributes & Traits (\(token.attributes.count))")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                            ForEach(token.attributes, id: \.name) { attr in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attr.name.uppercased())
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Text(attr.value)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 280, maxWidth: 360)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}
