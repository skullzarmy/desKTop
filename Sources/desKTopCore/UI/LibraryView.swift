import SwiftUI

/// Main desktop library management window
public struct LibraryView: View {
    @State private var sources: [WalletSource] = []
    @State private var tokens: [UnifiedToken] = []
    @State private var selectedToken: UnifiedToken?
    @State private var searchText: String = ""
    @State private var selectedCategory: MediaCategory? = nil
    @State private var isSourceSheetPresented: Bool = false
    @State private var rotationInterval: RotationInterval = .oneHour

    private let repository: WalletRepository
    private let onSetWallpaper: (UnifiedToken) -> Void

    public init(
        repository: WalletRepository = WalletRepository(),
        onSetWallpaper: @escaping (UnifiedToken) -> Void = { _ in }
    ) {
        self.repository = repository
        self.onSetWallpaper = onSetWallpaper
    }

    public var filteredTokens: [UnifiedToken] {
        tokens.filter { token in
            let matchesSearch = searchText.isEmpty ||
                token.name.localizedCaseInsensitiveContains(searchText) ||
                token.creators.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
                token.contract.localizedCaseInsensitiveContains(searchText)

            let matchesCategory = selectedCategory == nil || token.mediaCategory == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedCategory) {
                Section("Media Formats") {
                    NavigationLink(value: Optional<MediaCategory>.none) {
                        Label("All Art (\(tokens.count))", systemImage: "photo.stack")
                    }
                    NavigationLink(value: MediaCategory.staticImage) {
                        Label("Still Images", systemImage: "photo")
                    }
                    NavigationLink(value: MediaCategory.video) {
                        Label("Video & Loops", systemImage: "video")
                    }
                    NavigationLink(value: MediaCategory.animatedImage) {
                        Label("Animated GIFs", systemImage: "sparkles")
                    }
                    NavigationLink(value: MediaCategory.aleatory) {
                        Label("Aleatory Generative", systemImage: "dice")
                    }
                    NavigationLink(value: MediaCategory.bootloader) {
                        Label("Bootloader (BTLDR)", systemImage: "cpu")
                    }
                    NavigationLink(value: MediaCategory.fxhash) {
                        Label("fxhash & Interactive", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                Section("Sources (\(sources.count))") {
                    ForEach(sources) { source in
                        HStack {
                            Circle()
                                .fill(source.isEnabled ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(source.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text("\(source.tokenCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { isSourceSheetPresented = true }) {
                        Label("Manage Sources...", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }

                Section("Rotation Frequency") {
                    Picker("", selection: $rotationInterval) {
                        ForEach(RotationInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isSourceSheetPresented = true }) {
                        Label("Add Source", systemImage: "plus")
                    }
                }
            }
        } content: {
            // Main Art Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)], spacing: 16) {
                    ForEach(filteredTokens) { token in
                        TokenCardView(token: token, isSelected: selectedToken?.id == token.id) {
                            selectedToken = token
                        } onSetAsWallpaper: {
                            onSetWallpaper(token)
                        }
                    }
                }
                .padding(16)
            }
            .searchable(text: $searchText, prompt: "Search title, artist, or contract...")
            .navigationTitle("Art Collection")
        } detail: {
            // Inspector
            if let token = selectedToken {
                TokenInspectorView(token: token, onSetWallpaper: { onSetWallpaper(token) })
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select an artwork to inspect details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    private func reloadData() async {
        self.sources = await repository.getSources()
        self.tokens = await repository.getTokens()
    }
}

/// Token Card View inside Library Grid
struct TokenCardView: View {
    let token: UnifiedToken
    let isSelected: Bool
    let onSelect: () -> Void
    let onSetAsWallpaper: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Placeholder / Thumbnail Box
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(1.0, contentMode: .fit)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(token.mediaCategory.rawValue.capitalized)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(token.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !token.creators.isEmpty {
                    Text(token.creators.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            HStack {
                Button(action: onSetAsWallpaper) {
                    Text("Set Desktop")
                        .font(.caption2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            onSelect()
        }
    }
}

/// Token Detail Inspector pane
struct TokenInspectorView: View {
    let token: UnifiedToken
    let onSetWallpaper: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                Button(action: onSetWallpaper) {
                    Label("Set as macOS Wallpaper", systemImage: "display")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

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
                    DetailRow(label: "Format", value: token.mediaCategory.rawValue.capitalized)
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
