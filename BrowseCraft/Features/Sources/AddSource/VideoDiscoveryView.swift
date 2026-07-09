import SwiftUI

struct VideoDiscoveryView: View {
    private enum SearchState: Equatable {
        case idle
        case searching
        case finished
        case error(String)

        var isSearching: Bool {
            if case .searching = self {
                return true
            }

            return false
        }
    }

    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var siteURL: String = ""
    @State private var keyword: String = DiscoverVideoResourcesUseCase.defaultKeywords[0]
    @State private var customKeyword: String = ""
    @State private var keywordSuggestions: [String] = DiscoverVideoResourcesUseCase.defaultKeywords
    @State private var items: [TransientVideoDiscoveryItem] = []
    @State private var searchState: SearchState = .idle

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("URL", text: self.$siteURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .disabled(self.searchState.isSearching)

                    TextField("Search keyword", text: self.$keyword)
                        .disabled(self.searchState.isSearching)
                }

                Section("Keyword Suggestions") {
                    self.keywordChips
                }

                Section("Custom Keyword") {
                    HStack {
                        TextField("Keyword", text: self.$customKeyword)
                            .disabled(self.searchState.isSearching)

                        Button("Add") {
                            self.addCustomKeyword()
                        }
                        .disabled(self.canAddCustomKeyword == false)
                    }
                }

                Section {
                    Button(
                        action: {
                            Task {
                                await self.search()
                            }
                        },
                        label: {
                            HStack {
                                if self.searchState.isSearching {
                                    ProgressView()
                                }

                                Text(self.searchState.isSearching ? "Searching..." : "Search")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    )
                    .disabled(self.canSearch == false)
                } footer: {
                    Text("Temporary discovery only. Web pages open in Web Player; direct mp4/m3u8 links can use Native Player.")
                }

                self.statusSection

                if self.items.isEmpty == false {
                    Section("Results") {
                        ForEach(self.items) { item in
                            NavigationLink {
                                VideoDiscoveryDetailView(
                                    item: item,
                                    viewModel: self.viewModel
                                )
                            } label: {
                                VideoDiscoveryResultRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                    .disabled(self.searchState.isSearching)
                }
            }
        }
    }

    private var trimmedSiteURL: String {
        return self.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedKeyword: String {
        return self.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSearch: Bool {
        return self.trimmedSiteURL.isEmpty == false
            && self.trimmedKeyword.isEmpty == false
            && self.searchState.isSearching == false
    }

    private var trimmedCustomKeyword: String {
        return self.customKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddCustomKeyword: Bool {
        return self.trimmedCustomKeyword.isEmpty == false
            && self.searchState.isSearching == false
    }

    private var keywordChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(self.keywordSuggestions, id: \.self) { keyword in
                    Button(keyword) {
                        self.keyword = keyword
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(self.searchState.isSearching)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func addCustomKeyword() {
        let keyword: String = self.trimmedCustomKeyword
        guard keyword.isEmpty == false else {
            return
        }

        if self.keywordSuggestions.contains(keyword) == false {
            self.keywordSuggestions.append(keyword)
        }

        self.keyword = keyword
        self.customKeyword = ""
    }

    @ViewBuilder
    private var statusSection: some View {
        switch self.searchState {
        case .idle:
            EmptyView()
        case .searching:
            Section("Status") {
                Text("Searching video-like resources on this website...")
                    .foregroundStyle(.secondary)
            }
        case .finished:
            Section("Status") {
                Text(self.items.isEmpty ? "No temporary results found." : "Found \(self.items.count) temporary results.")
                    .foregroundStyle(self.items.isEmpty ? Color.secondary : Color.green)
            }
        case .error(let message):
            Section("Status") {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    @MainActor
    private func search() async {
        self.searchState = .searching
        self.viewModel.errorMessage = nil
        self.items = await self.viewModel.discoverVideoResources(
            siteURLString: self.trimmedSiteURL,
            keyword: self.trimmedKeyword
        )

        if self.items.isEmpty,
           let message: String = self.viewModel.errorMessage,
           message.isEmpty == false {
            self.searchState = .error(message)
            return
        }

        self.searchState = .finished
    }
}

private struct VideoDiscoveryResultRow: View {
    let item: TransientVideoDiscoveryItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ItemThumbnailImageView(
                urlString: self.item.coverURL,
                refererURLString: self.item.detailURL,
                requestConfig: nil
            )
            .frame(width: 74, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(self.item.title)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Image(systemName: self.item.playbackKind == .directMedia ? "play.circle.fill" : "safari")
                        .foregroundStyle(.blue)
                }

                Text(self.item.detailURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let latestText: String = self.item.latestText {
                    Text(latestText)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct VideoDiscoveryDetailView: View {
    let item: TransientVideoDiscoveryItem
    @ObservedObject var viewModel: SourcesViewModel

    var body: some View {
        Form {
            Section("Resource") {
                ItemThumbnailImageView(
                    urlString: self.item.coverURL,
                    refererURLString: self.item.detailURL,
                    requestConfig: nil
                )
                .aspectRatio(1.45, contentMode: .fit)
                .frame(maxWidth: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(self.item.title)
                    .font(.title3.weight(.semibold))

                if let latestText: String = self.item.latestText {
                    Text(latestText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Playback") {
                if let url: URL = URL(string: self.item.detailURL) {
                    NavigationLink {
                        VideoDiscoveryWebPlayerScreen(
                            url: url,
                            title: self.item.title
                        )
                    } label: {
                        Label("Open in Web Player", systemImage: "safari")
                    }

                    if self.item.playbackKind == .directMedia {
                        NavigationLink {
                            VideoDiscoveryNativePlayerScreen(
                                mediaURL: url,
                                title: self.item.title
                            )
                        } label: {
                            Label("Open in Native Player", systemImage: "play.circle")
                        }
                    } else {
                        Label("Native Player needs a direct mp4/m3u8 URL", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Temporary Detail") {
                LabeledContent("Keyword", value: self.item.matchedKeyword)
                LabeledContent("Source Page", value: self.item.sourcePageURL)
                LabeledContent("Playback Type", value: self.item.playbackKind == .directMedia ? "Direct Media" : "Web Page")
            }
        }
        .navigationTitle("Video Detail")
        .onAppear {
            self.saveTemporaryHistory()
        }
    }

    private func saveTemporaryHistory() {
        guard let resourceURL: URL = URL(string: self.item.detailURL) else {
            return
        }

        self.viewModel.saveTemporaryHistory(
            TemporaryResourceHistory(
                userID: AppUser.localDefaultID,
                kind: .video,
                title: self.item.title,
                resourceURL: resourceURL,
                coverURL: self.item.coverURL.flatMap(URL.init(string:)),
                sourcePageURL: URL(string: self.item.sourcePageURL),
                matchedKeyword: self.item.matchedKeyword,
                videoPlaybackKind: self.item.playbackKind == .directMedia ? .directMedia : .webPage,
                visitedAt: Date()
            )
        )
    }
}

private struct VideoDiscoveryWebPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let title: String

    var body: some View {
        VideoWebPlayerView(
            request: VideoWebPlayerRequest(url: self.url),
            title: self.title,
            controls: {
                EmptyView()
            },
            onClose: {
                self.dismiss()
            }
        )
        .navigationBarBackButtonHidden(true)
    }
}

private struct VideoDiscoveryNativePlayerScreen: View {
    @Environment(\.dismiss) private var dismiss

    let mediaURL: URL
    let title: String

    var body: some View {
        VideoNativePlayerView(
            mediaURL: self.mediaURL,
            requestConfig: nil,
            title: self.title,
            controls: {
                EmptyView()
            },
            onProgress: { _, _ in },
            onReadyToPlay: { _ in },
            onClose: {
                self.dismiss()
            }
        )
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
    }
}
