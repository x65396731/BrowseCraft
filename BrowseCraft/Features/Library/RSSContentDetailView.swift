import SwiftUI
import WebKit
import WebUI

// 中文注释：RSSContentDetailView 是 RSS 新闻详情画面。

struct RSSContentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RSSContentDetailViewModel
    @State private var selectedHeroImageIndex: Int = 0
    @State private var isShowingOriginalWebView: Bool = false

    init(viewModel: RSSContentDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Self.pageBackgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    self.heroCarousel
                        .frame(height: 384)

                    VStack(alignment: .leading, spacing: 24) {
                        Text(self.viewModel.displayItem.title)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Self.primaryTextColor)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        self.articleMetadataPanel

                        self.articleBody

                        if self.originalURL != nil {
                            Button {
                                self.isShowingOriginalWebView = true
                            } label: {
                                Label("Open Original", systemImage: "globe")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.top, 31)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Self.contentBackgroundColor)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 35,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 35,
                            style: .continuous
                        )
                    )
                    .offset(y: -25)
                }
            }

            self.topControls
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            CrashDiagnostics.shared.setScreen(.rssDetail)
            AppAnalytics.shared.logScreenView(.rssDetail)
            CrashDiagnostics.shared.setSource(self.viewModel.source)
            CrashDiagnostics.shared.setRuleStage(.rssFeed)
            self.viewModel.saveReadingHistoryIfNeeded()
            Task {
                await self.viewModel.loadDetailContentIfNeeded()
            }
        }
        .handlesRewardedAdPlayback(
            shouldPlayAd: self.viewModel.shouldPlayAd,
            markHandled: {
                self.viewModel.markAdPlaybackHandled()
            }
        )
        .fullScreenCover(isPresented: self.$isShowingOriginalWebView) {
            if let originalURL: URL = self.originalURL {
                RSSOriginalWebView(
                    url: originalURL,
                    title: self.viewModel.displayItem.title
                )
            }
        }
    }

    @ViewBuilder
    private var articleBody: some View {
        if let payload: RSSContentPayload = RSSContentPayload.decode(from: self.viewModel.displayItem.latestText),
           payload.blocks.isEmpty == false {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(payload.blocks.filter { block in block.kind != .image }.enumerated()), id: \.element.id) { index, block in
                    self.articleBlock(block)
                        .padding(.top, self.articleBlockTopPadding(block: block, index: index))
                }
            }
        } else if let summary: String = RSSContentTextFormatter.sanitized(self.viewModel.displayItem.latestText) {
            self.paragraphText(summary)
        }
    }

    @ViewBuilder
    private func articleBlock(_ block: RSSContentPayload.Block) -> some View {
        switch block.kind {
        case .subtitle:
            if let text: String = block.text {
                Text(text)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Self.primaryTextColor)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph:
            if let text: String = block.text {
                self.paragraphText(text)
            }
        case .image:
            if let imageURL: String = block.imageURL {
                CoverImageView(urlString: imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 190)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.vertical, 2)
            }
        }
    }

    private func articleBlockTopPadding(block: RSSContentPayload.Block, index: Int) -> CGFloat {
        guard index > 0 else {
            return 0
        }

        switch block.kind {
        case .subtitle:
            return 34
        case .paragraph:
            return 16
        case .image:
            return 20
        }
    }

    private func paragraphText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Self.primaryTextColor)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var heroCarousel: some View {
        ZStack(alignment: .bottom) {
            let imageURLs: [String] = self.heroImageURLs

            if imageURLs.isEmpty {
                self.heroPlaceholder
            } else {
                TabView(selection: self.$selectedHeroImageIndex) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, imageURL in
                        CoverImageView(urlString: imageURL)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if imageURLs.count > 1 {
                    self.heroPagination(count: imageURLs.count)
                        .padding(.bottom, 38)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var heroPlaceholder: some View {
        LinearGradient(
            colors: [
                Color(red: 58 / 255, green: 205 / 255, blue: 225 / 255),
                Color(red: 244 / 255, green: 249 / 255, blue: 250 / 255)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            Image(systemName: "newspaper")
                .font(.system(size: 54, weight: .light))
                .foregroundColor(Color.white.opacity(0.85))
        )
    }

    private func heroPagination(count: Int) -> some View {
        HStack(spacing: 24) {
            ForEach(self.visiblePaginationIndexes(count: count), id: \.self) { index in
                if index == self.selectedHeroImageIndex {
                    Image(systemName: "sparkle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 17, height: 18)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .frame(minWidth: 69, minHeight: 24)
        .animation(.easeInOut(duration: 0.2), value: self.selectedHeroImageIndex)
    }

    private func visiblePaginationIndexes(count: Int) -> [Int] {
        let maxVisibleCount: Int = 5
        guard count > maxVisibleCount else {
            return Array(0..<count)
        }

        let halfVisibleCount: Int = maxVisibleCount / 2
        let lowerBound: Int = max(0, min(self.selectedHeroImageIndex - halfVisibleCount, count - maxVisibleCount))
        return Array(lowerBound..<(lowerBound + maxVisibleCount))
    }

    private var heroImageURLs: [String] {
        var urls: [String] = []
        var seen: Set<String> = []

        func append(_ urlString: String?) {
            guard let urlString: String = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  urlString.isEmpty == false,
                  seen.contains(urlString) == false else {
                return
            }

            seen.insert(urlString)
            urls.append(urlString)
        }

        append(self.viewModel.displayItem.coverURL)

        if let payload: RSSContentPayload = RSSContentPayload.decode(from: self.viewModel.displayItem.latestText) {
            for block in payload.blocks where block.kind == .image {
                append(block.imageURL)
            }
        }

        return urls
    }

    @ViewBuilder
    private var articleMetadataPanel: some View {
        if let metadata: RSSContentPayload.Metadata = self.articleMetadata {
            VStack(spacing: 28) {
                if metadata.tags.isEmpty == false {
                    HStack(spacing: 22) {
                        ForEach(metadata.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Self.primaryTextColor.opacity(0.72))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(Self.metadataBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 32) {
                    if let likeCount: Int = metadata.likeCount {
                        self.metricChip(systemImage: "hand.thumbsup.fill", value: likeCount)
                    }

                    self.metricChip(systemImage: "text.bubble.fill", value: metadata.commentCount ?? 0)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricChip(systemImage: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))

            Text("\(value)")
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
        }
        .foregroundColor(Self.metricTextColor)
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(Self.metadataBackgroundColor)
        .clipShape(Capsule())
    }

    private var topControls: some View {
        HStack {
            Button(
                action: {
                    self.dismiss()
                },
                label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white, lineWidth: 2)
                        )
                }
            )
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 72)
    }

    private var articleMetadata: RSSContentPayload.Metadata? {
        guard let metadata: RSSContentPayload.Metadata = RSSContentPayload
            .decode(from: self.viewModel.displayItem.latestText)?
            .metadata else {
            return nil
        }

        if metadata.tags.isEmpty, metadata.likeCount == nil, metadata.commentCount == nil {
            return nil
        }

        return metadata
    }

    private var originalURL: URL? {
        return URL(string: self.viewModel.displayItem.detailURL)
    }

    private static let primaryTextColor: Color = Color(
        red: 25 / 255,
        green: 32 / 255,
        blue: 45 / 255
    )

    private static let secondaryTextColor: Color = Color(
        red: 147 / 255,
        green: 151 / 255,
        blue: 160 / 255
    )

    private static let metricTextColor: Color = Color(
        red: 88 / 255,
        green: 89 / 255,
        blue: 91 / 255
    )

    private static let accentColor: Color = Color(
        red: 84 / 255,
        green: 116 / 255,
        blue: 253 / 255
    )

    private static let pageBackgroundColor: Color = Color.white
    private static let contentBackgroundColor: Color = Color(
        red: 252 / 255,
        green: 252 / 255,
        blue: 252 / 255
    )
    private static let metadataBackgroundColor: Color = Color(
        red: 238 / 255,
        green: 238 / 255,
        blue: 238 / 255
    )
}

private struct RSSOriginalWebView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator: RSSOriginalWebCoordinator = RSSOriginalWebCoordinator()

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
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        HStack(spacing: 12) {
            Button {
                self.dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }

            Divider()
                .frame(height: 20)

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
private final class RSSOriginalWebCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let configuration: WKWebViewConfiguration

    override init() {
        let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
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
