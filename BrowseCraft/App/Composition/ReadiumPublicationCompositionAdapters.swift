import ReadiumShared

// 中文注释：把 Infrastructure 的 Readium 实现挂到阅读器声明的协议上。装配根是唯一同时认识
// Features 与 Infrastructure 的层，因此这层符合性只能写在这里；阅读器因此不再直接引用 Infrastructure 类型。

extension ReadiumBookPublicationHandle: ReadiumPublicationProviding {}

struct ReadiumSitePublicationBuilderAdapter: SiteReadiumPublicationBuilding {
    private let builder: ReadiumSitePublicationBuilder

    init(builder: ReadiumSitePublicationBuilder = ReadiumSitePublicationBuilder()) {
        self.builder = builder
    }

    func build(
        manifest: BookPublicationManifest,
        contentProvider: @escaping BookChapterContentProvider,
        audioFailureHandler: BookAudioResourceFailureHandler?
    ) -> Publication {
        return self.builder.build(manifest: manifest, contentProvider: contentProvider, audioFailureHandler: audioFailureHandler)
    }
}

/// 中文注释：书类 HLS 有声播放内核（fwq 设计稿第 83 节）：Infrastructure 的 `SiteHLSAudioPlayer` 与阅读器的接口同名同形，
/// 符合性与建内核的端口都挂在这里。
extension SiteHLSAudioPlayer: AudiobookPlaybackEngine {}

struct SiteHLSAudioEngineBuilderAdapter: SiteHLSAudioEngineBuilding {
    func makeEngine(
        publication: Publication,
        manifest: BookPublicationManifest,
        contentProvider: @escaping BookChapterContentProvider,
        initialLocation: Locator?,
        speed: Double,
        failureHandler: BookAudioResourceFailureHandler?,
        callbacks: AudiobookPlaybackCallbacks
    ) -> any AudiobookPlaybackEngine {
        return SiteHLSAudioPlayer(
            publication: publication,
            items: manifest.items,
            initialLocation: initialLocation,
            speed: speed,
            resolve: SiteHLSAudioPlayer.audioResolver(manifest: manifest, contentProvider: contentProvider),
            failureHandler: failureHandler,
            onPlaybackChange: callbacks.onPlaybackChange,
            onLocationChange: callbacks.onLocationChange,
            onResourceFinished: callbacks.onResourceFinished
        )
    }
}
