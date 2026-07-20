import SwiftUI

// 中文注释：RSSContentDetailView 是 RSS 新闻详情画面。

struct RSSContentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RSSContentDetailViewModel
    @State private var selectedHeroImageIndex: Int = 0
    @State private var isShowingOriginalWebView: Bool = false
    @State private var fullscreenMediaPlayerRequest: RSSMediaPlayerRequest?

    init(
        item: ContentItem,
        source: Source,
        factory: LibraryContentViewModelFactory
    ) {
        _viewModel = StateObject(
            wrappedValue: factory.makeRSSDetail(item, source)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            RSSContentDetailStyle.pageBackgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    RSSHeroCarouselView(
                        item: self.viewModel.displayItem,
                        originalURL: self.originalURL,
                        media: self.rssMedia,
                        selectedImageIndex: self.$selectedHeroImageIndex,
                        openMedia: self.openMedia
                    )
                        .frame(height: 384)

                    VStack(alignment: .leading, spacing: 24) {
                        Text(self.viewModel.displayItem.title)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(RSSContentDetailStyle.primaryTextColor)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        RSSArticleMetadataPanel(metadata: self.articleMetadata)

                        RSSArticleBodyView(
                            item: self.viewModel.displayItem,
                            originalURL: self.originalURL
                        )

                        if self.originalWebURL != nil {
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
                    .background(RSSContentDetailStyle.contentBackgroundColor)
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

            RSSContentDetailTopControls {
                self.dismiss()
            }
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
            if let originalURL: URL = self.originalWebURL {
                RSSOriginalWebView(
                    url: originalURL,
                    title: self.viewModel.displayItem.title
                )
            }
        }
        .fullScreenCover(item: self.$fullscreenMediaPlayerRequest) { request in
            RSSMediaPlayerView(
                media: request.media,
                title: request.title,
                onClose: {
                    self.fullscreenMediaPlayerRequest = nil
                }
            )
        }
    }

    private func openMedia(_ media: RSSContentPayload.Media) {
        self.fullscreenMediaPlayerRequest = RSSMediaPlayerRequest(
            media: media,
            title: self.viewModel.displayItem.title
        )
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

    private var rssMedia: RSSContentPayload.Media? {
        return (self.viewModel.displayItem.richContent
            ?? RSSContentPayload.decode(from: self.viewModel.displayItem.latestText))?.media
    }

    private var originalURL: URL? {
        guard let url: URL = URL(string: self.viewModel.displayItem.detailURL) else {
            return nil
        }

        return Self.secureOriginalURLIfNeeded(url)
    }

    private var originalWebURL: URL? {
        guard let url: URL = self.originalURL,
              Self.supportsOriginalWebViewURL(url) else {
            return nil
        }

        return url
    }

    static func supportsOriginalWebViewURL(_ url: URL) -> Bool {
        return url.scheme?.lowercased() != "http"
    }

    private static func secureOriginalURLIfNeeded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              let host: String = url.host?.lowercased(),
              Self.httpsPreferredOriginalHosts.contains(host),
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private static let httpsPreferredOriginalHosts: Set<String> = [
        "weixin.sogou.com",
        "www.jintiankansha.me"
    ]
}
