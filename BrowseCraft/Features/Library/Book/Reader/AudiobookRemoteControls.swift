import Foundation
import MediaPlayer
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

// 中文注释：锁屏 / 控制中心 / 耳机按键 → AudioNavigator；Now Playing 元数据由 Readium 自带的 NowPlayingInfo 写。
// 照抄 Readium TestApp 的 AudiobookViewController 命令中心部分；attach / detach 成对，避免命令目标泄漏。

@MainActor
final class AudiobookRemoteControls {
    private let navigator: AudioNavigator
    private let title: String
    private let chapterCount: Int
    private var targets: [(MPRemoteCommand, Any)] = []

    init(navigator: AudioNavigator, title: String, chapterCount: Int) {
        self.navigator = navigator
        self.title = title
        self.chapterCount = chapterCount
    }

    func attach() {
        NowPlayingInfo.shared.media = NowPlayingInfo.Media(title: self.title, chapterCount: self.chapterCount)
        let center: MPRemoteCommandCenter = MPRemoteCommandCenter.shared()
        self.on(center.playCommand) { navigator, _ in navigator.play() }
        self.on(center.pauseCommand) { navigator, _ in navigator.pause() }
        self.on(center.togglePlayPauseCommand) { navigator, _ in navigator.playPause() }
        self.on(center.previousTrackCommand) { navigator, _ in Task { await navigator.goBackward() } }
        self.on(center.nextTrackCommand) { navigator, _ in Task { await navigator.goForward() } }
        center.skipBackwardCommand.preferredIntervals = [10]
        self.on(center.skipBackwardCommand) { navigator, _ in Task { await navigator.seek(by: -10) } }
        center.skipForwardCommand.preferredIntervals = [30]
        self.on(center.skipForwardCommand) { navigator, _ in Task { await navigator.seek(by: 30) } }
        self.on(center.changePlaybackPositionCommand) { navigator, event in
            guard let event: MPChangePlaybackPositionCommandEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return
            }
            Task { await navigator.seek(to: event.positionTime) }
        }
    }

    func detach() {
        for (command, target) in self.targets {
            command.removeTarget(target)
        }
        self.targets.removeAll()
        NowPlayingInfo.shared.clear()
    }

    func update(info: MediaPlaybackInfo) {
        NowPlayingInfo.shared.playback = NowPlayingInfo.Playback(duration: info.duration, elapsedTime: info.time, rate: self.navigator.settings.speed)
        NowPlayingInfo.shared.media?.chapterNumber = info.resourceIndex + 1
        let center: MPRemoteCommandCenter = MPRemoteCommandCenter.shared()
        center.previousTrackCommand.isEnabled = self.navigator.canGoBackward
        center.nextTrackCommand.isEnabled = self.navigator.canGoForward
    }

    private func on(_ command: MPRemoteCommand, _ block: @escaping @MainActor (AudioNavigator, MPRemoteCommandEvent) -> Void) {
        let navigator: AudioNavigator = self.navigator
        let target: Any = command.addTarget { event in
            Task { @MainActor in
                block(navigator, event)
            }
            return .success
        }
        self.targets.append((command, target))
    }
}
