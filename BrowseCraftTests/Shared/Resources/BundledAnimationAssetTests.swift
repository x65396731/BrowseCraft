import AVFoundation
import XCTest
@testable import BrowseCraft

// 中文注释：两段随包视频是装饰性资产，重新编码（例如为了体积把 H.264 换成 HEVC）不会被任何既有用例发现，
// 一旦编码不被 AVFoundation 接受，表现是界面一片空白而不是崩溃或报错。这里把两条不变量固化下来：
// 资源必须存在且能解出可播放的视频轨；启动动画必须保留音轨——播放器显式 `isMuted = false`、`volume = 1`
// 并激活 ambient 会话，剥掉音轨会静默改变启动体验。
// （2026-09-18 把内购背景转成 HEVC 省下 4.5MB 时引入。）
final class BundledAnimationAssetTests: XCTestCase {
    func testPurchaseBackgroundIsPlayable() async throws {
        let url: URL = try BundledPurchaseAnimationResource().videoURL()
        let tracks: [AVAssetTrack] = try await Self.playableVideoTracks(at: url)
        XCTAssertFalse(tracks.isEmpty, "内购背景必须有可播放的视频轨")
    }

    func testPurchaseBackgroundPosterIsPresent() throws {
        let url: URL = try BundledPurchaseAnimationResource().posterURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testStartupAnimationIsPlayable() async throws {
        let url: URL = try BundledStartupAnimationResource().videoURL()
        let tracks: [AVAssetTrack] = try await Self.playableVideoTracks(at: url)
        XCTAssertFalse(tracks.isEmpty, "启动动画必须有可播放的视频轨")
    }

    /// 中文注释：启动动画有意带声音，见 `StartupVideoPlayerView` 里的 `isMuted = false` 与 ambient 会话。
    func testStartupAnimationKeepsItsAudioTrack() async throws {
        let url: URL = try BundledStartupAnimationResource().videoURL()
        let asset: AVURLAsset = AVURLAsset(url: url)
        let audioTracks: [AVAssetTrack] = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty, "启动动画的音轨是有意保留的，不能在压缩体积时被剥掉")
    }

    /// 中文注释：除了 `isPlayable`（只说明容器与轨道元数据能解析），还真解出一帧——
    /// 这一步才能发现「编码标记正确但解码器拿不到画面」的情况。
    private static func playableVideoTracks(at url: URL) async throws -> [AVAssetTrack] {
        let asset: AVURLAsset = AVURLAsset(url: url)
        let isPlayable: Bool = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "AVFoundation 判定该资产不可播放：\(url.lastPathComponent)")

        let generator: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let (image, _): (CGImage, CMTime) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        XCTAssertGreaterThan(image.width, 0, "解码出的帧宽度为 0：\(url.lastPathComponent)")
        XCTAssertGreaterThan(image.height, 0, "解码出的帧高度为 0：\(url.lastPathComponent)")

        return try await asset.loadTracks(withMediaType: .video)
    }
}
