import SwiftUI

/// Source Management Sheet for Wallets, Domains, Collections, and Curations
public struct SourceManagementSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sources: [WalletSource] = []
    @State private var inputString: String = ""
    @State private var isResolving: Bool = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let repository: WalletRepository
    private let onSourcesChanged: () -> Void

    public init(repository: WalletRepository, onSourcesChanged: @escaping () -> Void = {}) {
        self.repository = repository
        self.onSourcesChanged = onSourcesChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Manage Art Sources")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            Text("Add any Tezos public wallet address (tz1/tz2/tz3/tz4), Tezos Domain (e.g. alice.tez or builder.hack), collection contract (KT1), or objkt.com curation URL.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Input Row
            HStack {
                TextField("e.g. builder.hack or tz1VSUr8...", text: $inputString)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isResolving)

                Button("Add Source") {
                    Task {
                        await addSource()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
            }

            if isResolving {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(statusMessage ?? "Resolving and indexing art...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Text("Active Sources (\(sources.count))")
                    .font(.headline)

                Spacer()

                if !sources.isEmpty {
                    Button(action: {
                        Task {
                            for s in sources {
                                await syncSource(s)
                            }
                        }
                    }) {
                        Label("Sync All", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isResolving)
                }
            }

            List {
                ForEach(sources) { source in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.displayName)
                                .fontWeight(.medium)
                            switch source.type {
                            case .wallet(let address, let domain):
                                Text(domain != nil ? "\(domain!.normalized) • \(address.raw)" : address.raw)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            case .collection(let contract, _):
                                Text("Contract: \(contract.raw)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            case .objktCuration(let id, _):
                                Text("objkt.com Curation: \(id)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Text("\(source.tokenCount) art tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button {
                            Task {
                                await syncSource(source)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Re-fetch tokens for this source")
                        .disabled(isResolving)
                        .padding(.leading, 8)

                        Button(role: .destructive) {
                            Task {
                                try? await repository.removeSource(id: source.id)
                                await loadSources()
                                onSourcesChanged()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
        }
        .padding(20)
        .frame(width: 540, height: 460)
        .task {
            await loadSources()
        }
    }

    private func syncSource(_ source: WalletSource) async {
        isResolving = true
        statusMessage = "Syncing \(source.displayName)..."
        defer { isResolving = false }

        let tzkt = TzKTClient()
        let filter = FungibleFilterEngine()

        switch source.type {
        case .wallet(let address, _):
            do {
                let tokens = try await tzkt.fetchAllTokens(for: address) { count in
                    Task { @MainActor in
                        self.statusMessage = "Syncing \(source.displayName) (\(count) loaded)..."
                    }
                }
                let artTokens = filter.filter(tokens)
                var updated = source
                updated.tokenCount = artTokens.count
                try await repository.updateSource(updated)
                try await repository.upsertTokens(artTokens)
                await loadSources()
                onSourcesChanged()
            } catch {
                errorMessage = "Sync failed: \(error.localizedDescription)"
            }
        case .collection(let contract, _):
            do {
                let tokens = try await tzkt.fetchContractTokens(contract: contract, limit: 500)
                let artTokens = filter.filter(tokens)
                var updated = source
                updated.tokenCount = artTokens.count
                try await repository.updateSource(updated)
                try await repository.upsertTokens(artTokens)
                await loadSources()
                onSourcesChanged()
            } catch {
                errorMessage = "Sync failed: \(error.localizedDescription)"
            }
        case .objktCuration(let id, _):
            let objkt = ObjktClient()
            do {
                let tokens = try await objkt.fetchCurationTokens(slugOrId: id, limit: 500)
                let artTokens = filter.filter(tokens)
                var updated = source
                updated.tokenCount = artTokens.count
                try await repository.updateSource(updated)
                try await repository.upsertTokens(artTokens)
                await loadSources()
                onSourcesChanged()
            } catch {
                errorMessage = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadSources() async {
        self.sources = await repository.getSources()
    }

    private func addSource() async {
        let trimmed = inputString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isResolving = true
        errorMessage = nil
        statusMessage = "Analyzing input..."

        defer {
            isResolving = false
        }

        let resolver = TezosDomainsResolver()
        let tzkt = TzKTClient()
        let filter = FungibleFilterEngine()

        // 1. Check if domain
        if let domain = TezosDomain(trimmed) {
            statusMessage = "Resolving Tezos Domain \(domain.normalized)..."
            do {
                if let profile = try await resolver.resolve(domainInput: domain.normalized),
                   let address = TezosAddress(profile.address) {
                    statusMessage = "Fetching tokens for \(domain.normalized)..."
                    let tokens = try await tzkt.fetchAllTokens(for: address) { count in
                        Task { @MainActor in
                            self.statusMessage = "Fetching tokens for \(domain.normalized) (\(count) loaded)..."
                        }
                    }
                    let artTokens = filter.filter(tokens)

                    let source = WalletSource(
                        type: .wallet(address: address, domain: domain),
                        displayName: domain.normalized,
                        avatarUri: profile.avatarUri,
                        tokenCount: artTokens.count
                    )

                    try await repository.addSource(source)
                    try await repository.upsertTokens(artTokens)

                    inputString = ""
                    await loadSources()
                    onSourcesChanged()
                    return
                } else {
                    errorMessage = "Could not resolve domain '\(domain.normalized)'."
                    return
                }
            } catch {
                errorMessage = "Resolution failed: \(error.localizedDescription)"
                return
            }
        }

        // 2. Check if address
        if let address = TezosAddress(trimmed) {
            statusMessage = "Fetching tokens for \(address.raw)..."
            do {
                let reverseProfile = try? await resolver.reverseResolve(address: address)
                let domain = reverseProfile.flatMap { TezosDomain($0.domain) }

                let tokens = try await tzkt.fetchAllTokens(for: address) { count in
                    Task { @MainActor in
                        self.statusMessage = "Fetching tokens for \(address.raw) (\(count) loaded)..."
                    }
                }
                let artTokens = filter.filter(tokens)

                let source = WalletSource.fromAddress(
                    address,
                    domain: domain,
                    label: reverseProfile?.domain ?? address.raw
                )
                var mutableSource = source
                mutableSource.tokenCount = artTokens.count

                try await repository.addSource(mutableSource)
                try await repository.upsertTokens(artTokens)

                inputString = ""
                await loadSources()
                onSourcesChanged()
                return
            } catch {
                errorMessage = "Failed fetching tokens: \(error.localizedDescription)"
                return
            }
        }

        // 3. Check if objkt curation
        if trimmed.contains("objkt.com/curations") || trimmed.contains("objkt.com/gallery") || trimmed.count == 8 {
            let slug = trimmed.components(separatedBy: "/").last ?? trimmed
            statusMessage = "Querying objkt.com curation \(slug)..."

            let objkt = ObjktClient()
            do {
                let tokens = try await objkt.fetchCurationTokens(slugOrId: slug, limit: 200)
                let artTokens = filter.filter(tokens)

                let source = WalletSource.fromObjktCuration(curationId: slug, name: "Curation \(slug)")
                var mutableSource = source
                mutableSource.tokenCount = artTokens.count

                try await repository.addSource(mutableSource)
                try await repository.upsertTokens(artTokens)

                inputString = ""
                await loadSources()
                onSourcesChanged()
                return
            } catch {
                errorMessage = "Failed to query curation: \(error.localizedDescription)"
                return
            }
        }

        errorMessage = "Invalid input. Please enter a valid tz1/2/3/4/KT1 address, .tez domain, or objkt curation."
    }
}
