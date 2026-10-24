import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

// 中文注释：有声书播放内核的最小接口——播放页、锁屏控制与 VM 只用到这些。Readium `AudioNavigator` 套一层适配；
// HLS 音频（fwq 设计稿第 83 节）由 Infrastructure 的 `SiteHLSAudioPlayer` 实现同一接口，界面、续读、书签、锁屏不分叉。
// 与 `BookReaderPublicationPorts.swift` 同一种边界做法：协议与建内核的端口由阅读器声明，符合性挂在装配根 `App/Composition`。
// 跳转类方法另起名字：Readium 的 `go(to:)` / `goForward()` 带默认参数，不能直接当协议实现。

@MainActor
protocol AudiobookPlaybackEngine: AnyObject {
    /// 中文注释：播放中的速度（暂停时也是下次播放用的速度）。
    var speed: Double { get }
    var canGoForward: Bool { get }
    var canGoBackward: Bool { get }
    func play()
    func pause()
    func playPause()
    func seek(to time: Double) async
    func seek(by delta: Double) async
    func setSpeed(_ speed: Double)
    @discardableResult func skipToNextResource() async -> Bool
    @discardableResult func skipToPreviousResource() async -> Bool
    @discardableResult func jump(to locator: Locator) async -> Bool
    @discardableResult func jump(to link: Link) async -> Bool
    /// 中文注释：换掉这个内核（重试新建一个）前调用，交还音频会话；Readium 在自己的 deinit 里做，适配里不用管。
    func close()
}

extension AudioNavigator: AudiobookPlaybackEngine {
    var speed: Double {
        return self.settings.speed
    }

    func setSpeed(_ speed: Double) {
        self.submitPreferences(AudioPreferences(speed: speed))
    }

    func skipToNextResource() async -> Bool {
        return await self.goForward(options: NavigatorGoOptions())
    }

    func skipToPreviousResource() async -> Bool {
        return await self.goBackward(options: NavigatorGoOptions())
    }

    func jump(to locator: Locator) async -> Bool {
        return await self.go(to: locator, options: NavigatorGoOptions(animated: true))
    }

    func jump(to link: Link) async -> Bool {
        return await self.go(to: link, options: NavigatorGoOptions(animated: true))
    }

    func close() {}
}

/// 中文注释：内核报给 VM 的三类事件，`AudioNavigatorBridge` 与 `SiteHLSAudioPlayer` 共用同一组闭包。
struct AudiobookPlaybackCallbacks {
    let onPlaybackChange: @MainActor (MediaPlaybackInfo) -> Void
    let onLocationChange: @MainActor (Locator) -> Void
    let onResourceFinished: @MainActor (MediaPlaybackInfo) -> Void
}

/// 中文注释：建书类 HLS 有声播放内核的端口（实现是 Infrastructure 的 `SiteHLSAudioPlayer`，适配器在装配根）。
/// 不注入时 HLS 有声书仍交给 Readium（测试与预览走这条）。
@MainActor
protocol SiteHLSAudioEngineBuilding {
    func makeEngine(
        publication: Publication,
        manifest: BookPublicationManifest,
        contentProvider: @escaping BookChapterContentProvider,
        initialLocation: Locator?,
        speed: Double,
        failureHandler: BookAudioResourceFailureHandler?,
        callbacks: AudiobookPlaybackCallbacks
    ) -> any AudiobookPlaybackEngine
}
