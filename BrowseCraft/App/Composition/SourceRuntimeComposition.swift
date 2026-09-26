import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation

/// 中文注释：规则运行时组合体——网络载体与三种 runtime 的装配。
/// runtime 本身在 BrowseCraftRuntime 框架里，这里只负责把 App 的具体适配器
/// （Alamofire、WebView、Keychain 凭据、浏览器请求头）接到内核端口上。
@MainActor
final class SourceRuntimeComposition {
    let browserRequestHeaderProvider: any BrowserRequestHeaderProviding
    let systemCookieHeaderProvider: any SystemCookieHeaderProviding
    let sourceCredentialStore: SourceCredentialStoring
    let urlResolver: URLResolvingService
    let pageLoader: DefaultPageLoader
    let sourceRuntimeResolver: any SourceRuntimeResolving
    let protectedResourceLoader: ReaderProtectedResourceLoader

    init(sourceRepository: SourceRepository) {
        let urlResolver: URLResolvingService = URLResolvingService()
        self.urlResolver = urlResolver

        let sourceCredentialStore: SourceCredentialStoring = InMemorySourceCredentialStore()
        self.sourceCredentialStore = sourceCredentialStore

        let browserRequestHeaderProvider: any BrowserRequestHeaderProviding = SafariRequestHeaderProvider()
        self.browserRequestHeaderProvider = browserRequestHeaderProvider

        let systemCookieHeaderProvider: any SystemCookieHeaderProviding = SharedHTTPCookieHeaderProvider()
        self.systemCookieHeaderProvider = systemCookieHeaderProvider

        let httpClient: AlamofireHTTPClient = AlamofireHTTPClient(
            credentialProvider: sourceCredentialStore,
            browserRequestHeaderProvider: browserRequestHeaderProvider,
            systemCookieHeaderProvider: systemCookieHeaderProvider,
            managedAPIURLMatcher: { url in PortalAPIConfiguration.isManagedAPIURL(url) }
        )
        let pageLoader: DefaultPageLoader = DefaultPageLoader(
            httpContentLoader: httpClient,
            httpDataLoader: httpClient,
            credentialProvider: sourceCredentialStore,
            browserRequestHeaderProvider: browserRequestHeaderProvider,
            systemCookieHeaderProvider: systemCookieHeaderProvider,
            // 中文注释：needsWebView 页面的 DOM 稳定判定策略在此显式声明。`baseline` 是历史机制与历史取值
            // （轮询整页 outerHTML 长度，最小等待 6 次测量 + 5 × 300ms）。影视线已闭合并经真机复核，
            // 切换到 `.mutationQuietWindow` 需要先完成固定站点集合测量与真机复核，是一次显式改动。
            domStabilityPolicy: .baseline
        )
        self.pageLoader = pageLoader

        let sourceRuntimeFactory: SourceRuntimeFactory = SourceRuntimeFactory(
            comicSourceRuntimeFactory: ComicSourceRuntimeFactory(
                pageContentLoader: pageLoader,
                comicRuleParser: CoreComicRuleSourceParser(),
                urlResolver: urlResolver,
                defaultUserAgent: browserRequestHeaderProvider.userAgent
            ),
            videoSourceRuntimeFactory: Self.makeVideoRuntimeFactory(
                pageLoader: pageLoader,
                sourceCredentialStore: sourceCredentialStore
            ),
            // 中文注释：读书 kind 的运行时（批次 B）：列表 / 详情 / 章节正文或音频都按 BookSiteRule 走同一个 pageLoader。
            bookSourceRuntimeFactory: BookSourceRuntimeFactory(
                pageContentLoader: pageLoader,
                defaultUserAgent: browserRequestHeaderProvider.userAgent
            ),
            // 中文注释：槽位额度是 App 的决策，runtime 只调用注入的校验；
            // 这里以持久化状态为准，避免用内存里可能过期的 Source 判断。
            validateSourceAccess: { source in
                guard source.isBuiltIn == false else {
                    return
                }
                let reconciledSources: [Source] = try sourceRepository.reconcileSourceSlotAssignments()
                if let persistedSource: Source = reconciledSources.first(where: { candidate in
                    return candidate.id == source.id
                }) {
                    guard persistedSource.accessState == .active else {
                        throw SourceRepositoryError.sourceLockedBySlotLimit
                    }
                    return
                }
                guard source.accessState == .active else {
                    throw SourceRepositoryError.sourceLockedBySlotLimit
                }
            }
        )
        #if DEBUG
        // 中文注释：演示模式（`-BrowseCraftDemoMode`）下演示来源换成自造内容，其余来源照常走真实 runtime。
        self.sourceRuntimeResolver = DemoMode.isEnabled
            ? DemoSourceRuntimeResolver(base: sourceRuntimeFactory)
            : sourceRuntimeFactory
        #else
        self.sourceRuntimeResolver = sourceRuntimeFactory
        #endif

        self.protectedResourceLoader = ReaderProtectedResourceLoader(
            legacyLoader: ProtectedResourceLoader(
                dataLoader: pageLoader,
                decryptor: CommonCryptoProtectedResourceDecryptor(),
                defaultUserAgent: browserRequestHeaderProvider.userAgent
            ),
            pipelineExecutor: ResourcePipelineExecutor(
                dataLoader: pageLoader,
                cryptography: CommonCryptoResourcePipelineCryptography()
            )
        )
    }

    /// 中文注释：视频 runtime 工厂同时供正常播放链与 Debug 审计使用，装配保持一份。
    static func makeVideoRuntimeFactory(
        pageLoader: DefaultPageLoader,
        sourceCredentialStore: SourceCredentialStoring
    ) -> VideoSourceRuntimeFactory {
        return VideoSourceRuntimeFactory(
            pageContentLoader: pageLoader,
            parser: CoreVideoRuleSourceParser(),
            credentialProvider: sourceCredentialStore
        )
    }
}
