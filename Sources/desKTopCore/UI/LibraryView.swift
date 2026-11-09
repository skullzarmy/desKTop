import SwiftUI
import AppKit

/// Top-level sidebar selection targets
public enum LibrarySidebarItem: Hashable {
    case allArt
    case owned
    case created
    case collections
    case collection(String)    // contract address
    case customGallery(UUID)
    case objktCuration(String) // galleryId
}

/// Format category filter (UI filter, NOT hardcoded tabs)
public enum FormatFilter: String, CaseIterable, Identifiable {
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
public enum TokenSortOption: String, CaseIterable, Identifiable {
    case dateAcquired = "Date Added"
    case mintDate = "Mint Date (Token ID)"
    case title = "Title (A–Z)"
    case supply = "Edition Size"

    public var id: String { rawValue }
}

/// Direction for sorting
public enum SortDirection: String, CaseIterable, Identifiable {
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
public struct CollectionContractItem: Identifiable, Hashable {
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
    @State private var artistProfiles: [String: ArtistProfile] = ArtistResolver.loadCachedProfiles()
    @State private var fxhashProjects: [String: FxhashProjectInfo] = FxhashResolver.loadCachedProjects()

    @State private var selectedSidebarItem: LibrarySidebarItem = .allArt
    @State private var selectedToken: UnifiedToken?
    @State private var isInspectorPresented: Bool = false
    @State private var currentWallpaperTokenId: String?

    // Filters and controls
    @State private var searchText: String = ""
    @State private var collectionSearchText: String = ""
    @State private var selectedFormatFilter: FormatFilter = .all
    @State private var selectedContractFilter: String? = nil
    @State private var sortOption: TokenSortOption = .dateAcquired
    @State private var sortDirection: SortDirection = .descending
    @State private var gridSize: Double = 180

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

    public func artistDisplayName(for addressOrName: String) -> String {
        let trimmed = addressOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profile = artistProfiles[trimmed] ?? artistProfiles[trimmed.lowercased()] {
            return profile.displayName
        }
        guard trimmed.count > 10 else { return trimmed }
        return String(trimmed.prefix(6)) + "…" + String(trimmed.suffix(4))
    }

    public func artistProfile(for addressOrName: String) -> ArtistProfile? {
        let trimmed = addressOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        return artistProfiles[trimmed] ?? artistProfiles[trimmed.lowercased()]
    }

    private func isTokenCreatedByUser(_ token: UnifiedToken) -> Bool {
        if token.isCreated { return true }
        let sourceAddresses = Set(sources.compactMap { $0.walletAddress?.lowercased() })
        for creator in token.creators {
            if sourceAddresses.contains(creator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                return true
            }
        }
        return false
    }

    private var ownedTokensCount: Int {
        tokens.filter { $0.isOwned }.count
    }

    private var createdTokensCount: Int {
        tokens.filter { $0.isCreated || isTokenCreatedByUser($0) }.count
    }

    // MARK: - Filtered Tokens Calculation

    public var displayedTokens: [UnifiedToken] {
        // 1. Filter by top-level sidebar selection
        var baseTokens: [UnifiedToken]
        switch selectedSidebarItem {
        case .allArt:
            baseTokens = tokens
        case .owned:
            baseTokens = tokens.filter { $0.isOwned }
        case .created:
            baseTokens = tokens.filter { $0.isCreated || isTokenCreatedByUser($0) }
        case .collections:
            baseTokens = tokens
        case .customGallery(let gid):
            if let gallery = galleries.first(where: { $0.id == gid }) {
                let idSet = Set(gallery.tokenIds)
                baseTokens = tokens.filter { idSet.contains($0.id) }
            } else {
                baseTokens = []
            }
        case .objktCuration(let cid):
            baseTokens = tokens.filter { $0.rawMetadata?["curationId"] == cid }
        case .collection(let key):
            if key.hasPrefix("fxhash:") {
                let targetProj = String(key.dropFirst(7)).lowercased()
                baseTokens = tokens.filter { $0.isFxhash && (resolvedProjectName(for: $0).lowercased() == targetProj) }
            } else {
                baseTokens = tokens.filter { $0.contract.lowercased() == key.lowercased() }
            }
        }

        // 2. Filter by search text
        if !searchText.isEmpty {
            baseTokens = baseTokens.filter { token in
                token.name.localizedCaseInsensitiveContains(searchText) ||
                token.creators.contains(where: { creator in
                    creator.localizedCaseInsensitiveContains(searchText) ||
                    artistDisplayName(for: creator).localizedCaseInsensitiveContains(searchText) ||
                    (artistProfile(for: creator)?.tzdomain?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (artistProfile(for: creator)?.twitterHandle?.localizedCaseInsensitiveContains(searchText) ?? false)
                }) ||
                token.contract.localizedCaseInsensitiveContains(searchText) ||
                (resolvedName(for: token.contract).localizedCaseInsensitiveContains(searchText)) ||
                token.tokenId.contains(searchText)
            }
        }

        // 3. Filter by format filter
        if selectedFormatFilter != .all {
            baseTokens = baseTokens.filter { selectedFormatFilter.matches($0.mediaCategory) }
        }

        // 4. Filter by collection filter
        if let contractFilter = selectedContractFilter, !contractFilter.isEmpty {
            baseTokens = baseTokens.filter { $0.contract.lowercased() == contractFilter.lowercased() }
        }

        // 5. Apply sorting
        let isAsc = (sortDirection == .ascending)
        baseTokens.sort { a, b in
            switch sortOption {
            case .dateAcquired:
                let dateA = a.acquiredDate ?? Date.distantPast
                let dateB = b.acquiredDate ?? Date.distantPast
                if dateA != dateB {
                    return isAsc ? (dateA < dateB) : (dateA > dateB)
                }
                let idA = Int(a.tokenId) ?? 0
                let idB = Int(b.tokenId) ?? 0
                return isAsc ? (idA < idB) : (idA > idB)

            case .mintDate:
                let idA = Int(a.tokenId) ?? 0
                let idB = Int(b.tokenId) ?? 0
                return isAsc ? (idA < idB) : (idA > idB)

            case .title:
                let compare = a.name.localizedCaseInsensitiveCompare(b.name)
                return isAsc ? (compare == .orderedAscending) : (compare == .orderedDescending)

            case .supply:
                let supA = a.supply ?? 1
                let supB = b.supply ?? 1
                return isAsc ? (supA < supB) : (supA > supB)
            }
        }

        return baseTokens
    }

    public func resolvedProjectName(for token: UnifiedToken) -> String {
        if let info = fxhashProjects[token.id], let p = info.projectName, !p.isEmpty {
            return p
        }
        return token.fxhashProjectName ?? "fxhash (\(token.fxhashVersion ?? "Generative"))"
    }

    public func collectionTokenMatches(token: UnifiedToken, key: String) -> Bool {
        if key.hasPrefix("fxhash:") {
            let targetProj = String(key.dropFirst(7)).lowercased()
            return token.isFxhash && (resolvedProjectName(for: token).lowercased() == targetProj)
        }
        return token.contract.caseInsensitiveCompare(key) == .orderedSame
    }

    /// Derived list of unique collections/projects with token counts dynamically scoped to the current context
    private var uniqueCollections: [CollectionContractItem] {
        var normalCounts: [String: Int] = [:]
        var fxhashCounts: [String: (count: Int, version: String?)] = [:]

        let scopedTokens: [UnifiedToken]
        switch selectedSidebarItem {
        case .created:
            scopedTokens = tokens.filter { $0.isCreated || isTokenCreatedByUser($0) }
        case .owned:
            scopedTokens = tokens.filter { $0.isOwned }
        case .customGallery(let gid):
            if let gallery = galleries.first(where: { $0.id == gid }) {
                let idSet = Set(gallery.tokenIds)
                scopedTokens = tokens.filter { idSet.contains($0.id) }
            } else {
                scopedTokens = []
            }
        case .objktCuration(let cid):
            scopedTokens = tokens.filter { $0.rawMetadata?["curationId"] == cid }
        default:
            scopedTokens = tokens
        }

        for t in scopedTokens {
            if t.isFxhash {
                let projName = resolvedProjectName(for: t)
                let current = fxhashCounts[projName] ?? (0, t.fxhashVersion)
                fxhashCounts[projName] = (current.count + 1, t.fxhashVersion ?? current.version)
            } else {
                normalCounts[t.contract, default: 0] += 1
            }
        }

        var items: [CollectionContractItem] = []

        // 1. FA2 & standard NFT contracts
        for (contract, count) in normalCounts {
            items.append(CollectionContractItem(
                contract: contract,
                displayName: resolvedName(for: contract),
                count: count
            ))
        }

        // 2. fxhash Generative Projects (differentiated into their true projects!)
        for (projName, val) in fxhashCounts {
            items.append(CollectionContractItem(
                contract: "fxhash:\(projName)",
                displayName: projName,
                count: val.count,
                fxhashVersion: val.version
            ))
        }

        return items.sorted { $0.count > $1.count }
    }

    public func resolvedName(for contract: String) -> String {
        if contract.hasPrefix("fxhash:") {
            return String(contract.dropFirst(7))
        }
        let lower = contract.lowercased()
        if let name = collectionNames[contract] ?? collectionNames[lower] {
            return name
        }
        return defaultContractAlias(for: contract)
    }

    private func defaultContractAlias(for contract: String) -> String {
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
                        Text("\(ownedTokensCount)")
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
                        Text("\(createdTokensCount)")
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
                        Text("\(uniqueCollections.count)")
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
                        HStack {
                            Label(gallery.name, systemImage: "sparkles.rectangle.stack")
                            Spacer()
                            if gallery.isActiveForRotation {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                    .help("Active rotation gallery")
                            }
                            Text("\(gallery.tokenIds.count)")
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
                    let isColRotating: Bool = {
                        if case .collection(let activeContract, _) = activeRotationTarget {
                            return activeContract.caseInsensitiveCompare(colKey) == .orderedSame
                        }
                        return false
                    }()

                    TokenInspectorView(
                        token: token,
                        collectionName: colDisplay,
                        collectionTokensCount: colCount,
                        artistProfile: token.creators.first.flatMap { artistProfile(for: $0) },
                        artistDisplayName: token.creators.first.map { artistDisplayName(for: $0) } ?? (token.creators.first ?? "Unknown"),
                        fxhashProjectInfo: fxhashProjects[token.id],
                        isLiveOnDesktop: currentWallpaperTokenId == token.tokenId,
                        isCollectionRotating: isColRotating,
                        galleries: galleries,
                        matteMode: $matteMode,
                        customHex: $customHex,
                        onSetWallpaper: {
                            currentWallpaperTokenId = token.tokenId
                            onSetWallpaper(token)
                        },
                        onRotateCollection: {
                            startRotatingCurrentScope(.collection(contract: colKey, displayName: colDisplay))
                        },
                        onAddToGallery: { gid in
                            Task {
                                try? await repository.addTokenToGallery(tokenId: token.id, galleryId: gid)
                                await reloadData()
                            }
                        },
                        onFilterByCollection: { contract in
                            selectedSidebarItem = .collection(contract)
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
            // Breadcrumbs header if viewing a specific collection
            if case .collection(let contract) = selectedSidebarItem {
                HStack(spacing: 8) {
                    Button(action: {
                        selectedSidebarItem = .collections
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("All Collections")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.link)

                    Text("/")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text(resolvedName(for: contract))
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Button("Open on objkt.com") {
                        if let url = URL(string: "https://objkt.com/collections/\(contract)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.06))
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
                        ForEach(displayedTokens) { token in
                            let cardColName = token.isFxhash ? resolvedProjectName(for: token) : resolvedName(for: token.contract)
                            TokenCardView(
                                token: token,
                                collectionName: cardColName,
                                artistName: token.creators.first.map { artistDisplayName(for: $0) } ?? "",
                                isSelected: selectedToken?.id == token.id,
                                isLiveOnDesktop: currentWallpaperTokenId == token.tokenId,
                                galleries: galleries,
                                onSelect: {
                                    selectedToken = token
                                },
                                onSetAsWallpaper: {
                                    currentWallpaperTokenId = token.tokenId
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
                    }
                    .padding(16)
                }
            }
            .searchable(text: $searchText, prompt: "Search title, creator, or collection…")
        }
        .navigationTitle(navigationTitleString)
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

                if isCurrentScopeRotating {
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
            return .collection(contract: contract, displayName: resolvedName(for: contract))
        case .customGallery(let gid):
            let name = galleries.first(where: { $0.id == gid })?.name ?? "Gallery"
            return .customGallery(id: gid, name: name)
        case .objktCuration(let cid):
            let name = objktCurations.first(where: { $0.galleryId == cid })?.name ?? "Curation"
            return .objktCuration(id: cid, name: name)
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
        case (.collection(let c1, _), .collection(let c2, _)):
            return c1.caseInsensitiveCompare(c2) == .orderedSame
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
            return resolvedName(for: contract)
        case .customGallery(let gid):
            return galleries.first(where: { $0.id == gid })?.name ?? "Gallery"
        case .objktCuration(let cid):
            return objktCurations.first(where: { $0.galleryId == cid })?.name ?? "Curation"
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
        newGalleryDesc = "Created from \(currentScopeTitle) with \(tokensToAddToNewGallery.count) artworks"
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
            if case .collection(_, let displayName) = activeRotationTarget {
                HStack(spacing: 10) {
                    Circle().fill(isRotationPaused ? Color.orange : Color.green).frame(width: 8, height: 8)
                    Text(isRotationPaused ? "Desktop Rotation Paused:" : "Live Desktop Rotation:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(isRotationPaused ? .orange : .green)
                    Text(displayName)
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
                        let isRotating: Bool = {
                            if case .collection(let activeContract, _) = activeRotationTarget {
                                return activeContract.caseInsensitiveCompare(col.contract) == .orderedSame
                            }
                            return false
                        }()

                        CollectionCardView(
                            item: col,
                            previewTokens: tokens.filter { collectionTokenMatches(token: $0, key: col.contract) }.prefix(4),
                            isRotating: isRotating,
                            onSelect: {
                                selectedSidebarItem = .collection(col.contract)
                            },
                            onStartRotating: {
                                startRotatingCurrentScope(.collection(contract: col.contract, displayName: col.displayName))
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
            return uniqueCollections
        }
        return uniqueCollections.filter {
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
            Text("New desKTop Gallery")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Gallery Name")
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

                Button("Create Gallery") {
                    let name = newGalleryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    Task {
                        let g = try? await repository.createGallery(name: name, description: newGalleryDesc.isEmpty ? nil : newGalleryDesc)
                        if let g = g, !tokensToAddToNewGallery.isEmpty {
                            for tid in tokensToAddToNewGallery {
                                try? await repository.addTokenToGallery(tokenId: tid, galleryId: g.id)
                            }
                        }
                        tokensToAddToNewGallery = []
                        await reloadData()
                        isNewGallerySheetPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGalleryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Data Synchronization

    private func reloadData() async {
        self.sources = await repository.getSources()
        self.tokens = await repository.getTokens()
        self.galleries = await repository.getGalleries()
        self.objktCurations = await repository.getObjktCurations()
        self.activeRotationTarget = await repository.getActiveRotationTarget()
        self.isRotationPaused = await repository.isRotationPaused()
        self.isRotationShuffle = await repository.isRotationShuffle()
        let intervalSec = await repository.getRotationInterval()
        self.rotationInterval = RotationInterval(rawValue: intervalSec) ?? .fiveMinutes
        resolveTopCollections()
        resolveArtists()
        resolveFxhashProjects()
    }

    private func resolveTopCollections() {
        let contracts = Array(Set(tokens.map { $0.contract }))
        guard !contracts.isEmpty else { return }
        Task {
            let names = await CollectionResolver.shared.resolveNames(for: contracts)
            await MainActor.run {
                self.collectionNames.merge(names) { _, new in new }
            }
        }
    }

    private func resolveArtists() {
        let creators = Array(Set(tokens.flatMap(\.creators)))
        guard !creators.isEmpty else { return }
        Task {
            let resolved = await ArtistResolver.shared.resolveArtists(for: creators)
            await MainActor.run {
                self.artistProfiles.merge(resolved) { _, new in new }
            }
        }
    }

    private func resolveFxhashProjects() {
        let fxTokens = tokens.filter { $0.isFxhash }
        guard !fxTokens.isEmpty else { return }
        Task {
            let resolved = await FxhashResolver.shared.resolveProjects(for: fxTokens)
            await MainActor.run {
                self.fxhashProjects.merge(resolved) { _, new in new }
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
    let onSelect: () -> Void
    let onStartRotating: () -> Void

    @State private var isHovered: Bool = false

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
                                    .clipped()
                            }
                            if gridTokens.indices.contains(1) {
                                ArtworkThumbnailView(token: gridTokens[1], contentMode: .fill)
                                    .clipped()
                            }
                        }
                        HStack(spacing: 2) {
                            if gridTokens.indices.contains(2) {
                                ArtworkThumbnailView(token: gridTokens[2], contentMode: .fill)
                                    .clipped()
                            }
                            if gridTokens.indices.contains(3) {
                                ArtworkThumbnailView(token: gridTokens[3], contentMode: .fill)
                                    .clipped()
                            }
                        }
                    }
                }

                // Rotating badge on preview
                if isRotating {
                    Text("LIVE ON DESKTOP")
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
                    Text("\(item.count) artworks")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(item.shortContract)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 4)

            // 1-Click Rotate Action Button
            Button(action: onStartRotating) {
                HStack(spacing: 4) {
                    Image(systemName: isRotating ? "checkmark.circle.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(isRotating ? "Rotating on Desktop" : "Rotate on Desktop")
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRotating ? Color.green : Color.accentColor)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(10)
        .background(isHovered ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isRotating ? Color.green.opacity(0.5) : (isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15)), lineWidth: isRotating ? 2 : 1)
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
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
    let galleries: [DesktopGallery]
    let onSelect: () -> Void
    let onSetAsWallpaper: () -> Void
    let onAddToGallery: (UUID) -> Void
    let onFilterByCollection: (String) -> Void
    let onRemoveFromCurrentGallery: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Artwork Image Box (Strictly bounded geometry so GIFs or WebViews can never overflow)
            GeometryReader { geo in
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.15)

                    ArtworkThumbnailView(token: token, contentMode: .fill, isHovered: isHovered)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // Top Left Live Badge
                    if isLiveOnDesktop {
                        VStack {
                            HStack {
                                Text("LIVE ON DESKTOP")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                                    .shadow(radius: 2)
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }

                    // Bottom Right Category Badge
                    Text(token.mediaCategory.rawValue.capitalized)
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
        .onHover { isHovered = $0 }
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
        cache.countLimit = 150
        cache.totalCostLimit = 120 * 1024 * 1024 // 120MB
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

        if let cached = ImageMemoryCache.shared.object(forKey: url as NSURL) {
            self.image = cached
            return
        }

        isLoading = true
        hasFailed = false

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15.0
            request.setValue("desKTop/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let img = NSImage(data: data) {
                ImageMemoryCache.shared.setObject(img, forKey: url as NSURL)
                self.image = img
                self.isLoading = false
            } else {
                self.hasFailed = true
                self.isLoading = false
            }
        } catch {
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
        let uri = token.thumbnailUri ?? token.displayUri ?? token.artifactUri
        guard let uri = uri else { return nil }
        return IPFSGatewayManager.resolvePublicURL(for: uri)
    }

    public var body: some View {
        if token.mediaCategory == .animatedImage, let url = targetURL {
            AnimatedGIFView(url: url, contentMode: contentMode, animates: shouldAnimate || isHovered)
                .clipped()
        } else if let url = targetURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.secondary.opacity(0.08)
                        ProgressView()
                            .controlSize(.small)
                    }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .clipped()
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
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
    let isCollectionRotating: Bool
    let galleries: [DesktopGallery]
    @Binding var matteMode: WallpaperMatteMode
    @Binding var customHex: String
    let onSetWallpaper: () -> Void
    let onRotateCollection: () -> Void
    let onAddToGallery: (UUID) -> Void
    let onFilterByCollection: (String) -> Void

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

                    Button(action: onRotateCollection) {
                        HStack(spacing: 6) {
                            Image(systemName: isCollectionRotating ? "checkmark.circle.fill" : "play.fill")
                            Text(isCollectionRotating ? "Rotating on Desktop" : (token.isFxhash ? "Rotate Project on Desktop" : "Rotate Collection on Desktop"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCollectionRotating ? Color.green : Color.accentColor)
                    .controlSize(.regular)

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
                Button(action: onSetWallpaper) {
                    Label(isLiveOnDesktop ? "Currently on Desktop" : "Set as Desktop Wallpaper", systemImage: "display")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

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
                    DetailRow(label: "Format Category", value: token.mediaCategory.rawValue.capitalized)
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
