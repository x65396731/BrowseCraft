import SwiftUI
import WebKit
import WebUI

struct ComicDiscoveryView: View {
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
    @State private var keyword: String = DiscoverComicResourcesUseCase.defaultKeywords[0]
    @State private var customKeyword: String = ""
    @State private var keywordSuggestions: [String] = DiscoverComicResourcesUseCase.defaultKeywords
    @State private var items: [TransientComicDiscoveryItem] = []
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
                }

                self.statusSection

                if self.items.isEmpty == false {
                    Section("Results") {
                        ForEach(self.items) { item in
                            NavigationLink {
                                ComicDiscoveryDetailView(item: item)
                            } label: {
                                ComicDiscoveryResultRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Comics")
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
                Text("Searching comic-like resources on this website...")
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
        self.items = await self.viewModel.discoverComicResources(
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

private struct ComicDiscoveryResultRow: View {
    let item: TransientComicDiscoveryItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ItemThumbnailImageView(
                urlString: self.item.coverURL,
                refererURLString: self.item.detailURL,
                requestConfig: nil
            )
            .frame(width: 64, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(self.item.title)
                    .font(.headline)
                    .lineLimit(2)

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

private struct ComicDiscoveryDetailView: View {
    let item: TransientComicDiscoveryItem

    var body: some View {
        Form {
            Section("Resource") {
                ItemThumbnailImageView(
                    urlString: self.item.coverURL,
                    refererURLString: self.item.detailURL,
                    requestConfig: nil
                )
                .aspectRatio(0.72, contentMode: .fit)
                .frame(maxWidth: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(self.item.title)
                    .font(.title3.weight(.semibold))

                if let latestText: String = self.item.latestText {
                    Text(latestText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Temporary Detail") {
                LabeledContent("Keyword", value: self.item.matchedKeyword)
                LabeledContent("Source Page", value: self.item.sourcePageURL)

                if let url: URL = URL(string: self.item.detailURL) {
                    NavigationLink {
                        ComicDiscoveryWebResourceView(
                            url: url,
                            title: self.item.title
                        )
                    } label: {
                        Label("Open Resource", systemImage: "globe")
                    }
                }
            }
        }
        .navigationTitle("Comic Detail")
    }
}

private struct ComicDiscoveryWebResourceView: View {
    @StateObject private var coordinator: ComicDiscoveryWebResourceCoordinator = ComicDiscoveryWebResourceCoordinator()

    let url: URL
    let title: String

    var body: some View {
        WebViewReader { proxy in
            VStack(spacing: 0) {
                self.toolbar(proxy: proxy)

                ProgressView(value: proxy.estimatedProgress)
                    .opacity(proxy.isLoading ? 1 : 0.12)

                WebView(configuration: self.coordinator.configuration)
                    .uiDelegate(self.coordinator)
                    .navigationDelegate(self.coordinator)
                    .allowsBackForwardNavigationGestures(true)
                    .allowsLinkPreview(false)
                    .contentInsetAdjustmentBehavior(.never)
                    .refreshable()
                    .onAppear {
                        proxy.load(request: URLRequest(url: self.url))
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(Color(.systemBackground))
        }
        .navigationTitle(self.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        HStack(spacing: 12) {
            Button {
                proxy.goBack()
            } label: {
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(.iconOnly)
            }
            .disabled(proxy.canGoBack == false)

            Button {
                proxy.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.forward")
                    .labelStyle(.iconOnly)
            }
            .disabled(proxy.canGoForward == false)

            Button {
                proxy.reload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(proxy.title?.isEmpty == false ? proxy.title ?? self.title : self.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text((proxy.url ?? self.url).host() ?? self.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

@MainActor
private final class ComicDiscoveryWebResourceCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let configuration: WKWebViewConfiguration

    override init() {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        self.configuration = configuration

        super.init()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let requestURL: URL = navigationAction.request.url else {
            return nil
        }

        webView.load(URLRequest(url: requestURL))
        return nil
    }
}
