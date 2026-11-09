import SwiftUI
import AppKit

/// Top-level sidebar selection targets
public enum LibrarySidebarItem: Hashable {
    case allArt
    case owned
    case created
    case customGallery(UUID)
    case objktCuration(String) // galleryId
    case collection(String)    // contract address
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

/// Sort options for artwork collection
public enum TokenSortOption: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case titleAsc = "Title (A – Z)"
    case titleDesc = "Title (Z – A)"
    case supplyAsc = "Edition Size (Low – High)"
    case supplyDesc = "Edition Size (High – Low)"

    public var id: String { rawValue }
}

/// Summary of unique contracts in the collection
public struct CollectionContractItem: Identifiable, Hashable {
    public var id: String { contract }
    public let contract: String
    public let displayName: String
    public let count: Int
}

/// Main desktop library management window
public struct LibraryView: View {
    @State private var sources: [WalletSource] = []
    @State private var tokens: [UnifiedToken] = []
    @State private var galleries: [DesktopGallery] = []
    @State private var objktCurations: [ObjktGallerySummary] = []
    @State private var collectionNames: [String: String] = [:]

    @State private var selectedSidebarItem: LibrarySidebarItem = .allArt
    @State private var selectedToken: UnifiedToken?
    @State private var currentWallpaperTokenId: String?

    // Filters and controls
    @State private var searchText: String = ""
    @State private var selectedFormatFilter: FormatFilter = .all
    @State private var selectedContractFilter: String? = nil
    @State private var sortOption: TokenSortOption = .recentlyAdded
    @State private var gridSize: Double = 180

    // Sheets & modals
    @State private var isSourceSheetPresented: Bool = false
    @State private var isNewGallerySheetPresented: Bool = false
    @State private var newGalleryName: String = ""
    @State private var newGalleryDesc: String = ""
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
        tokens.filter { isTokenCreatedByUser($0) }.count
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
            baseTokens = tokens.filter { isTokenCreatedByUser($0) }
        case .customGallery(let gid):
            if let gallery = galleries.first(where: { $0.id == gid }) {
                let idSet = Set(gallery.tokenIds)
                baseTokens = tokens.filter { idSet.contains($0.id) }
            } else {
                baseTokens = []
            }
        case .objktCuration(let cid):
            // Match tokens belonging to curation if any
            baseTokens = tokens.filter { $0.rawMetadata?["curationId"] == cid }
        case .collection(let contract):
            baseTokens = tokens.filter { $0.contract.lowercased() == contract.lowercased() }
        }

        // 2. Filter by search text
        if !searchText.isEmpty {
            baseTokens = baseTokens.filter { token in
                token.name.localizedCaseInsensitiveContains(searchText) ||
                token.creators.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
                token.contract.localizedCaseInsensitiveContains(searchText) ||
                token.tokenId.contains(searchText)
            }
        }

        // 3. Filter by format filter
        if selectedFormatFilter != .all {
            baseTokens = baseTokens.filter { selectedFormatFilter.matches($0.mediaCategory) }
        }

        // 4. Filter by collection dropdown
        if let contractFilter = selectedContractFilter, !contractFilter.isEmpty {
            baseTokens = baseTokens.filter { $0.contract.lowercased() == contractFilter.lowercased() }
        }

        // 5. Apply sorting
        switch sortOption {
        case .recentlyAdded:
            break
        case .titleAsc:
            baseTokens.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .titleDesc:
            baseTokens.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .supplyAsc:
            baseTokens.sort { ($0.supply ?? 1) < ($1.supply ?? 1) }
        case .supplyDesc:
            baseTokens.sort { ($0.supply ?? 1) > ($1.supply ?? 1) }
        }

        return baseTokens
    }

    /// Derived list of unique contracts with token counts
    private var uniqueCollections: [CollectionContractItem] {
        var counts: [String: Int] = [:]
        for t in tokens {
            counts[t.contract, default: 0] += 1
        }

        return counts.map { contract, count in
            let lower = contract.lowercased()
            let displayName = collectionNames[contract] ?? collectionNames[lower] ?? defaultContractAlias(for: contract)
            return CollectionContractItem(contract: contract, displayName: displayName, count: count)
        }
        .sorted { $0.count > $1.count }
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

                // Section: Collections / Contracts
                if !uniqueCollections.isEmpty {
                    Section("Collections") {
                        ForEach(uniqueCollections.prefix(25)) { col in
                            HStack {
                                Label(col.displayName, systemImage: "rectangle.stack")
                                    .lineLimit(1)
                                Spacer()
                                Text("\(col.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tag(LibrarySidebarItem.collection(col.contract))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSidebarItem = .collection(col.contract)
                            }
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
        } content: {
            // Main Content: Filter bar + Artwork Grid
            VStack(spacing: 0) {
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
                                TokenCardView(
                                    token: token,
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
                .searchable(text: $searchText, prompt: "Search title, creator, or contract…")
            }
            .navigationTitle(navigationTitleString)
        } detail: {
            // Inspector Pane
            if let token = selectedToken {
                TokenInspectorView(
                    token: token,
                    isLiveOnDesktop: currentWallpaperTokenId == token.tokenId,
                    galleries: galleries,
                    onSetWallpaper: {
                        currentWallpaperTokenId = token.tokenId
                        onSetWallpaper(token)
                    },
                    onAddToGallery: { gid in
                        Task {
                            try? await repository.addTokenToGallery(tokenId: token.id, galleryId: gid)
                            await reloadData()
                        }
                    }
                )
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select an artwork to inspect details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Right-click any artwork to set wallpaper or add to a desKTop gallery")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
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

    // MARK: - Subviews

    private var filterToolbar: some View {
        HStack(spacing: 10) {
            // Format Filter Menu
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
                HStack(spacing: 5) {
                    Image(systemName: "photo")
                        .font(.caption)
                    Text(selectedFormatFilter.rawValue)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)

            // Collection Dropdown Filter
            Menu {
                Button("All Collections") {
                    selectedContractFilter = nil
                }
                Divider()
                ForEach(uniqueCollections) { col in
                    Button(action: {
                        selectedContractFilter = col.contract
                    }) {
                        if selectedContractFilter == col.contract {
                            Label("\(col.displayName) (\(col.count))", systemImage: "checkmark")
                        } else {
                            Text("\(col.displayName) (\(col.count))")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.stack")
                        .font(.caption)
                    let title = selectedContractFilter.flatMap { c in uniqueCollections.first(where: { $0.contract == c })?.displayName } ?? "All Collections"
                    Text(title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)

            // Sort Menu
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
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text(sortOption.rawValue)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)

            Spacer()

            // Grid Size Slider
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(value: $gridSize, in: 130...280)
                    .frame(width: 80)
                Image(systemName: "square.grid.2x2")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Sync Button
            Button(action: {
                Task {
                    await syncAllSources()
                }
            }) {
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .help("Sync all sources and curations")
            .disabled(isSyncing)
        }
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
            return "No created artworks indexed yet. Sync your sources to query minted pieces from objkt."
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
        case .customGallery(let gid):
            let name = galleries.first(where: { $0.id == gid })?.name ?? "Gallery"
            return "\(name) (\(displayedTokens.count))"
        case .objktCuration(let cid):
            let name = objktCurations.first(where: { $0.galleryId == cid })?.name ?? "Curation"
            return "\(name) (\(displayedTokens.count))"
        case .collection(let contract):
            let displayName = collectionNames[contract] ?? collectionNames[contract.lowercased()] ?? defaultContractAlias(for: contract)
            return "\(displayName) (\(displayedTokens.count))"
        }
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
                        _ = try? await repository.createGallery(name: name, description: newGalleryDesc.isEmpty ? nil : newGalleryDesc)
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
        resolveTopCollections()
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

    private func syncAllSources() async {
        isSyncing = true
        defer { isSyncing = false }

        let tzkt = TzKTClient()
        let filter = FungibleFilterEngine()
        let objkt = ObjktClient()

        for source in sources {
            switch source.type {
            case .wallet(let address, _):
                // 1. Fetch all owned tokens from TzKT
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

                // 2. Fetch created art tokens from objkt GraphQL
                if let created = try? await objkt.fetchCreatedTokens(creator: address, limit: 500) {
                    let artCreated = filter.filter(created)
                    try? await repository.upsertTokens(artCreated)
                }

                // 3. Fetch objkt curations for this wallet
                if let curations = try? await objkt.fetchUserGalleries(curator: address) {
                    try? await repository.setObjktCurations(curations)

                    // Also fetch tokens from each curation
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

// MARK: - Artwork Card View

struct TokenCardView: View {
    let token: UnifiedToken
    let isSelected: Bool
    let isLiveOnDesktop: Bool
    let galleries: [DesktopGallery]
    let onSelect: () -> Void
    let onSetAsWallpaper: () -> Void
    let onAddToGallery: (UUID) -> Void
    let onRemoveFromCurrentGallery: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Artwork Image Box
            ZStack(alignment: .bottomTrailing) {
                Color.secondary.opacity(0.08)

                ArtworkThumbnailView(token: token, contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
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
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1.0, contentMode: .fit)
            .clipped()
            .cornerRadius(8)

            // Metadata info
            VStack(alignment: .leading, spacing: 2) {
                Text(token.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !token.creators.isEmpty {
                    Text(token.creators.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
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

            Button("View on objkt.com") {
                if let url = URL(string: "https://objkt.com/tokens/\(token.contract)/\(token.tokenId)") {
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

// MARK: - Native Animated GIF Player View

final class NonExpandingImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        layer?.masksToBounds = true
    }
}

public struct AnimatedGIFView: NSViewRepresentable {
    let url: URL?
    let contentMode: ContentMode

    public init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    public func makeNSView(context: Context) -> NSImageView {
        let view = NonExpandingImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    public func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.imageScaling = .scaleProportionallyUpOrDown
        nsView.animates = true
        guard let url = url else {
            nsView.image = nil
            return
        }

        if nsView.tag != url.hashValue {
            nsView.tag = url.hashValue
            Task.detached(priority: .userInitiated) {
                if let data = try? Data(contentsOf: url),
                   let img = NSImage(data: data) {
                    await MainActor.run {
                        nsView.image = img
                        nsView.animates = true
                    }
                }
            }
        }
    }
}

// MARK: - Artwork Thumbnail Loader

public struct ArtworkThumbnailView: View {
    let token: UnifiedToken
    let contentMode: ContentMode

    public init(token: UnifiedToken, contentMode: ContentMode = .fill) {
        self.token = token
        self.contentMode = contentMode
    }

    private var targetURL: URL? {
        let uri = token.thumbnailUri ?? token.displayUri ?? token.artifactUri
        guard let uri = uri else { return nil }
        return IPFSGatewayManager.resolvePublicURL(for: uri)
    }

    public var body: some View {
        if token.mediaCategory == .animatedImage, let url = targetURL {
            AnimatedGIFView(url: url, contentMode: contentMode)
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
    let isLiveOnDesktop: Bool
    let galleries: [DesktopGallery]
    let onSetWallpaper: () -> Void
    let onAddToGallery: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Large Preview
                ArtworkThumbnailView(token: token, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .background(Color.black.opacity(0.12))
                    .cornerRadius(8)

                // Title & Artists
                VStack(alignment: .leading, spacing: 4) {
                    Text(token.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    if !token.creators.isEmpty {
                        Text("Created by \(token.creators.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

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

                if let desc = token.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.headline)
                        Text(desc)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Token Details")
                        .font(.headline)

                    DetailRow(label: "Contract", value: token.contract)
                    DetailRow(label: "Token ID", value: token.tokenId)
                    DetailRow(label: "Format Category", value: token.mediaCategory.rawValue.capitalized)
                    if let supply = token.supply {
                        DetailRow(label: "Edition Supply", value: "\(supply)")
                    }
                    if let mime = token.mimeType {
                        DetailRow(label: "MIME Type", value: mime)
                    }
                    if let uri = token.artifactUri {
                        DetailRow(label: "Artifact URI", value: uri)
                    }
                }

                if !token.attributes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attributes & Traits")
                            .font(.headline)

                        ForEach(token.attributes, id: \.name) { attr in
                            HStack {
                                Text(attr.name)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(attr.value)
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
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
