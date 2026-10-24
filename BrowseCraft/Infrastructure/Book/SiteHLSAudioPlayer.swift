import AVFoundation
import BrowseCraftLog
import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

// 中文注释：站点有声书的 HLS 播放内核（fwq 设计稿第 83 节）。Readium `AudioNavigator` 把章节地址改成自定义 scheme
// 交给 AVPlayer，所有请求经资源加载器——单文件（mp3 / m4a）成立，HLS 不成立：相对切片按自定义 scheme 地址解析后
// 不是出版物里登记的链接，加载失败；绝对切片又绕过 `SiteBookAudioHTTPClient` 直连、不带 Referer（otomekoe 的
// m3u8 与切片不带同站 Referer 都是 403）。这里直接用 https 地址建 `AVURLAsset`，请求头放进
// `AVURLAssetHTTPHeaderFieldsKey`——对播放列表与切片都生效；App 的影视原生播放器（KSPlayer `KSOptions.appendHeader`）
// 用的是同一个键。请求头与 `SiteBookAudioHTTPClient` 同口径：规则给的头，缺 Referer 时以章节页为 Referer。
// 播放状态、Locator 与 Readium `AudioNavigator` 同形（`t=` 片段、progression），续读、书签、锁屏控制照旧。
// 清理不放 deinit（MainActor 类的 deinit 不能碰播放器）：时间刷新是持弱引用的 Task，KVO 随对象释放失效，
// 换内核时 VM 调 `close()` 交还音频会话。接口与阅读器的 `AudiobookPlaybackEngine` 同名同形，符合性挂在装配根。

@MainActor
final class SiteHLSAudioPlayer: NSObject, @preconcurrency AudioSessionUser {
    /// 中文注释：章节 → 实际播放地址与请求头；播放页型章节取页解析（`SiteBookPageAudioResolver`），直链原样。
    typealias AudioResolver = @Sendable (BookPublicationItem) async throws -> SiteBookResolvedAudio

    static let httpHeaderFieldsKey: String = "AVURLAssetHTTPHeaderFieldsKey"
    private static let refreshInterval: UInt64 = 500_000_000

    private let publication: Publication
    private let items: [BookPublicationItem]
    private let resolve: AudioResolver
    private let failureHandler: BookAudioResourceFailureHandler?
    private let onPlaybackChange: @MainActor (MediaPlaybackInfo) -> Void
    private let onLocationChange: @MainActor (Locator) -> Void
    private let onResourceFinished: @MainActor (MediaPlaybackInfo) -> Void
    private let initialLocation: Locator?
    private let player: AVPlayer = AVPlayer()
    private let audioSession: AudioSession = AudioSession.shared
    private(set) var speed: Double
    private var resourceIndex: Int = 0
    private var playTask: Task<Void, Never>? {
        willSet {
            self.playTask?.cancel()
        }
    }
    private var refreshTask: Task<Void, Never>?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var lastReportedState: MediaPlaybackState?

    init(
        publication: Publication,
        items: [BookPublicationItem],
        initialLocation: Locator?,
        speed: Double,
        resolve: @escaping AudioResolver,
        failureHandler: BookAudioResourceFailureHandler?,
        onPlaybackChange: @escaping @MainActor (MediaPlaybackInfo) -> Void,
        onLocationChange: @escaping @MainActor (Locator) -> Void,
        onResourceFinished: @escaping @MainActor (MediaPlaybackInfo) -> Void
    ) {
        self.publication = publication
        self.items = items
        self.initialLocation = initialLocation
        self.speed = speed
        self.resolve = resolve
        self.failureHandler = failureHandler
        self.onPlaybackChange = onPlaybackChange
        self.onLocationChange = onLocationChange
        self.onResourceFinished = onResourceFinished
        super.init()
        self.player.allowsExternalPlayback = false
        self.timeControlObservation = self.player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.timeControlStatusDidChange()
            }
        }
    }

    deinit {
        self.playTask?.cancel()
        self.refreshTask?.cancel()
    }

    // MARK: - 播放

    func play() {
        self.playTask = Task { @MainActor in
            self.audioSession.start(with: self, isPlaying: false)
            if self.player.currentItem == nil {
                let loaded: Bool
                if let location: Locator = self.initialLocation {
                    loaded = await self.jump(to: location)
                } else {
                    loaded = await self.load(resourceAt: 0, time: 0)
                }
                guard loaded, Task.isCancelled == false else {
                    return
                }
            }
            self.player.playImmediately(atRate: Float(self.speed))
            self.startRefreshing()
        }
    }

    func pause() {
        self.playTask = nil
        self.player.pause()
    }

    func playPause() {
        switch Self.state(of: self.player.timeControlStatus) {
        case .loading, .playing:
            self.pause()
        case .paused:
            self.play()
        }
    }

    func seek(to time: Double) async {
        let wasPlaying: Bool = self.player.timeControlStatus != .paused
        self.player.pause()
        await self.seekCurrentItem(to: time)
        self.reportPlayback()
        if wasPlaying {
            self.play()
        }
    }

    func seek(by delta: Double) async {
        await self.seek(to: self.currentTime + delta)
    }

    func setSpeed(_ speed: Double) {
        self.speed = speed
        // 中文注释：与 Readium 一致：暂停中不改 rate（改了会直接开播），下次 `play()` 按新速度。
        if self.player.timeControlStatus != .paused {
            self.player.rate = Float(speed)
        }
    }

    var canGoForward: Bool {
        return self.publication.readingOrder.indices.contains(self.resourceIndex + 1)
    }

    var canGoBackward: Bool {
        return self.publication.readingOrder.indices.contains(self.resourceIndex - 1)
    }

    @discardableResult
    func skipToNextResource() async -> Bool {
        return await self.jumpToResource(at: self.resourceIndex + 1)
    }

    @discardableResult
    func skipToPreviousResource() async -> Bool {
        return await self.jumpToResource(at: self.resourceIndex - 1)
    }

    @discardableResult
    func jump(to locator: Locator) async -> Bool {
        guard let index: Int = self.publication.readingOrder.firstIndexWithHREF(locator.href) else {
            return false
        }
        let wasPlaying: Bool = self.player.timeControlStatus != .paused
        let duration: Double? = (index == self.resourceIndex) ? self.resourceDuration : self.publication.readingOrder[index].duration
        let time: Double = locator.locations.time?.begin ?? ((duration ?? 0) * (locator.locations.progression ?? 0))
        let loaded: Bool = await self.load(resourceAt: index, time: time)
        if loaded, wasPlaying {
            self.player.playImmediately(atRate: Float(self.speed))
        }
        return loaded
    }

    @discardableResult
    func jump(to link: Link) async -> Bool {
        guard let index: Int = self.publication.readingOrder.firstIndexWithHREF(link.url()) else {
            return false
        }
        return await self.jumpToResource(at: index)
    }

    func close() {
        self.pause()
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.audioSession.end(for: self)
    }

    // MARK: - 加载

    private func jumpToResource(at index: Int) async -> Bool {
        guard self.publication.readingOrder.indices.contains(index) else {
            return false
        }
        let wasPlaying: Bool = self.player.timeControlStatus != .paused
        let loaded: Bool = await self.load(resourceAt: index, time: 0)
        if loaded, wasPlaying {
            self.player.playImmediately(atRate: Float(self.speed))
        }
        return loaded
    }

    /// 中文注释：换到第 index 集（同一集只 seek）。取播放地址失败时报单集失败（`APP-MEMO-043`），不换掉当前的播放项。
    private func load(resourceAt index: Int, time: Double) async -> Bool {
        guard self.items.indices.contains(index) else {
            return false
        }
        if self.player.currentItem == nil || index != self.resourceIndex {
            let item: BookPublicationItem = self.items[index]
            let resolved: SiteBookResolvedAudio
            do {
                resolved = try await self.resolve(item)
            } catch {
                AppLog.error(.network, "audio-hls-resolve-failed", ["path": .path(item.chapterURL), "error": .error(error)])
                self.reportFailure(
                    chapterURL: item.chapterURL,
                    kind: SiteBookAudioHTTPClient.failureKind(resolverError: error),
                    statusCode: SiteBookAudioHTTPClient.statusCode(of: error)
                )
                return false
            }
            let playerItem: AVPlayerItem = AVPlayerItem(asset: Self.asset(for: resolved))
            self.observeStatus(of: playerItem, chapterURL: item.chapterURL)
            NotificationCenter.default.removeObserver(self, name: AVPlayerItem.didPlayToEndTimeNotification, object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.playerItemDidPlayToEnd(_:)),
                name: AVPlayerItem.didPlayToEndTimeNotification,
                object: playerItem
            )
            self.player.replaceCurrentItem(with: playerItem)
            self.resourceIndex = index
            AppLog.info(.playback, "audio-hls-item-loaded", [
                "index": .int(index),
                "host": .host(resolved.url),
                "headers": .int(resolved.headers.count)
            ])
            if time <= 0 {
                // 中文注释：新换上的播放项本来就从头开始，不 seek（取不到的项上 seek 不会返回）。
                self.reportPlayback()
                return true
            }
        }
        await self.seekCurrentItem(to: time)
        self.reportPlayback()
        return true
    }

    /// 中文注释：在已失败的播放项上 seek，完成回调永远不来（2026-10-24 模拟器实网探针：otomekoe 不带 Referer 时卡死），失败项上直接跳过。
    private func seekCurrentItem(to time: Double) async {
        guard let item: AVPlayerItem = self.player.currentItem, item.status != .failed else {
            return
        }
        await self.player.seek(to: CMTime(seconds: max(time, 0), preferredTimescale: 1000))
    }

    /// 中文注释：http 先升 https（App 没有全局 ATS 例外，与 `SiteBookAudioHTTPClient` 同口径）；请求头为空时不带选项。
    static func asset(for resolved: SiteBookResolvedAudio) -> AVURLAsset {
        let url: URL = Self.upgradedToHTTPS(resolved.url)
        guard resolved.headers.isEmpty == false else {
            return AVURLAsset(url: url)
        }
        return AVURLAsset(url: url, options: [Self.httpHeaderFieldsKey: resolved.headers])
    }

    static func upgradedToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }

    /// 中文注释：出版物章节 → 播放地址的解析器：播放页型章节（`audioResolvedFromPage`）取页解析，章节地址本身是音频时原样。
    static func audioResolver(manifest: BookPublicationManifest, contentProvider: @escaping BookChapterContentProvider) -> AudioResolver {
        let pageChapters: [URL] = manifest.items.filter(\.audioResolvedFromPage).map(\.chapterURL)
        let pageResolver: SiteBookPageAudioResolver? = pageChapters.isEmpty
            ? nil
            : SiteBookPageAudioResolver(chapters: pageChapters, provider: contentProvider)
        return { item in
            if item.audioResolvedFromPage,
               let pageResolver: SiteBookPageAudioResolver = pageResolver,
               let resolved: SiteBookResolvedAudio = try await pageResolver.resolve(item.chapterURL) {
                return resolved
            }
            return SiteBookResolvedAudio(url: item.chapterURL, headers: [:])
        }
    }

    // MARK: - 状态上报

    private var currentTime: Double {
        let seconds: Double = self.player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    private var resourceDuration: Double? {
        if let duration: CMTime = self.player.currentItem?.duration, duration.isNumeric {
            let seconds: Double = duration.seconds
            return seconds.isFinite ? seconds : nil
        }
        return self.publication.readingOrder.indices.contains(self.resourceIndex)
            ? self.publication.readingOrder[self.resourceIndex].duration
            : nil
    }

    private var playbackInfo: MediaPlaybackInfo {
        return MediaPlaybackInfo(
            resourceIndex: self.resourceIndex,
            state: Self.state(of: self.player.timeControlStatus),
            time: self.currentTime,
            duration: self.resourceDuration
        )
    }

    static func state(of status: AVPlayer.TimeControlStatus) -> MediaPlaybackState {
        switch status {
        case .paused:
            return .paused
        case .waitingToPlayAtSpecifiedRate:
            return .loading
        case .playing:
            return .playing
        @unknown default:
            return .loading
        }
    }

    /// 中文注释：与 Readium `AudioNavigator.makeLocator` 同形：`t=` 片段、集内 progression；站点书没有各集时长，totalProgression 为 nil。
    static func locator(for link: Link, time: Double, duration: Double?) -> Locator {
        var progression: Double?
        if let duration: Double = duration, duration > 0 {
            progression = time / max(duration, 1)
        }
        return Locator(
            href: link.url(),
            mediaType: link.mediaType ?? MediaType("audio/*")!,
            title: link.title,
            locations: Locator.Locations(fragments: ["t=\(time)"], progression: progression)
        )
    }

    private func reportPlayback() {
        let info: MediaPlaybackInfo = self.playbackInfo
        if self.publication.readingOrder.indices.contains(self.resourceIndex), self.player.currentItem != nil {
            self.onLocationChange(
                Self.locator(for: self.publication.readingOrder[self.resourceIndex], time: info.time, duration: info.duration)
            )
        }
        self.onPlaybackChange(info)
    }

    private func startRefreshing() {
        guard self.refreshTask == nil else {
            return
        }
        self.refreshTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: Self.refreshInterval) // try?: 只在 Task 取消时抛，取消后下一轮 while 退出
                guard let self: SiteHLSAudioPlayer = self else {
                    return
                }
                // 中文注释：暂停中只在状态刚变时报一次（`timeControlStatusDidChange`），这里不重复刷。
                if self.player.timeControlStatus != .paused {
                    self.reportPlayback()
                }
            }
        }
    }

    private func timeControlStatusDidChange() {
        let state: MediaPlaybackState = Self.state(of: self.player.timeControlStatus)
        self.audioSession.user(self, didChangePlaying: state != .paused)
        guard state != self.lastReportedState else {
            return
        }
        self.lastReportedState = state
        self.reportPlayback()
    }

    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        guard let item: AVPlayerItem = notification.object as? AVPlayerItem, item == self.player.currentItem else {
            return
        }
        self.onResourceFinished(self.playbackInfo)
        guard self.canGoForward else {
            return
        }
        Task { @MainActor in
            if await self.jumpToResource(at: self.resourceIndex + 1) {
                self.play()
            }
        }
    }

    // MARK: - 失败

    private func observeStatus(of item: AVPlayerItem, chapterURL: URL) {
        self.itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else {
                return
            }
            let statusCode: Int? = Self.httpStatusCode(in: item)
            let failure: (any Error)? = item.error
            Task { @MainActor in
                AppLog.error(.network, "audio-hls-item-failed", [
                    "path": .path(chapterURL),
                    "status": .int(statusCode ?? 0),
                    "error": failure.map { .error($0) } ?? .code("unknown")
                ])
                self?.reportFailure(
                    chapterURL: chapterURL,
                    kind: statusCode.map(BookAudioResourceFailure.kind(statusCode:)) ?? .unavailable,
                    statusCode: statusCode
                )
            }
        }
    }

    /// 中文注释：AVFoundation 的 HTTP 失败不直接给状态码：播放项错误是 `NSURLErrorDomain -1102`，底层 `CoreMediaErrorDomain -12660`
    /// 的说明里才写着「HTTP 403: Forbidden」（界面语言是中文时这段也是英文原样）；错误日志有说明时也可能写在那里。
    /// 先看错误日志，再看播放项错误连同底层错误的完整描述（2026-10-24 模拟器实网探针：otomekoe 不带 Referer 时错误日志为空）。
    nonisolated static func httpStatusCode(in item: AVPlayerItem) -> Int? {
        let comments: [String] = (item.errorLog()?.events ?? []).compactMap(\.errorComment)
        if let code: Int = comments.reversed().lazy.compactMap(Self.httpStatusCode(inComment:)).first {
            return code
        }
        if let code: Int = item.error.flatMap({ Self.httpStatusCode(inComment: String(describing: $0)) }) {
            return code
        }
        return Self.httpStatusCode(fromURLError: item.error)
    }

    /// 中文注释：单文件音频（mp3 / m4a）HTTP 失败时错误日志与描述里都没有「HTTP 404」字样，播放项只给 `NSURLErrorDomain`：
    /// 404 是 -1100（文件不存在）、403 是 -1102（无权读取）。按状态码还原，归类才与 Readium 那条路（`SiteBookAudioHTTPClient`
    /// 拿得到状态码）一致——2026-10-24 leting8 第 1 集音频 404，改走本内核后只报 -1100，被当成「暂时不稳」而不是「已失效」。
    nonisolated static func httpStatusCode(fromURLError error: (any Error)?) -> Int? {
        guard let error: NSError = error.map({ $0 as NSError }), error.domain == NSURLErrorDomain else {
            return nil
        }
        switch error.code {
        case NSURLErrorFileDoesNotExist:
            return 404
        case NSURLErrorNoPermissionsToReadFile:
            return 403
        default:
            return nil
        }
    }

    nonisolated static func httpStatusCode(inComment comment: String) -> Int? {
        guard let range: Range<String.Index> = comment.range(of: #"HTTP\s*(\d{3})"#, options: .regularExpression) else {
            return nil
        }
        return Int(comment[range].filter(\.isNumber))
    }

    private func reportFailure(chapterURL: URL, kind: BookAudioResourceFailure.Kind, statusCode: Int?) {
        AppLog.notice(.network, "audio-chapter-unavailable", [
            "host": .host(chapterURL),
            "path": .path(chapterURL),
            "kind": .code(kind == .gone ? "gone" : "unavailable"),
            "status": .int(statusCode ?? 0)
        ])
        self.failureHandler?(BookAudioResourceFailure(chapterURL: chapterURL, kind: kind, statusCode: statusCode))
    }
}
