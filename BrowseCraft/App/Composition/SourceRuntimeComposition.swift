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
    let sourceRuntimeFactory: SourceRuntimeFactory
    let protectedResourceLoader: ReaderProtectedResourceLoader

    init(sourceRepository: SourceRepository) {
        let urlResolver: URLResolvingService = URLResolvingService()
        self.urlResolver = urlResolver

        let sourceCredentialStore: SourceCredentialStoring = InMemorySourceCredentialStore()
        self.sourceCredentialStore = sourceCredentialStore

        let browserRequestHeaderProvider: any BrowserRequestHeaderProviding = ChromeRequestHeaderProvider()
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
            systemCookieHeaderProvider: systemCookieHeaderProvider
        )
        self.pageLoader = pageLoader

        self.sourceRuntimeFactory = SourceRuntimeFactory(
            comicSourceRuntimeFactory: ComicSourceRuntimeFactory(
                pageContentLoader: pageLoader,
                comicRuleParser: CoreComicRuleSourceParser(),
                urlResolver: urlResolver,
                defaultUserAgent: browserRequestHeaderProvider.userAgent
            ),
            rssSourceRuntimeFactory: RSSSourceRuntimeFactory(
                pageContentLoader: pageLoader,
                pageDataLoader: pageLoader
            ),
            videoSourceRuntimeFactory: Self.makeVideoRuntimeFactory(
                pageLoader: pageLoader,
                sourceCredentialStore: sourceCredentialStore
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
