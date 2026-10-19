import BrowseCraftDomain
import Foundation
import ReadiumShared
import Testing
import UIKit
@testable import BrowseCraft

// 中文注释：有声书播放页（docs/design/Audiobook-Player-Page-Redesign-Design.md）：单集失效分类（fwq `APP-MEMO-043`）、倍速记忆、封面取色。

struct AudiobookResourceFailureClassificationTests {
    /// 只有 404 / 403 / 410 算站点上已失效，其余可重试。
    @Test func goneOnlyForRemovedStatusCodes() {
        for code in [403, 404, 410] {
            #expect(BookAudioResourceFailure.kind(statusCode: code) == .gone)
        }
        for code in [401, 429, 500, 502, 503] {
            #expect(BookAudioResourceFailure.kind(statusCode: code) == .unavailable)
        }
    }

    /// 播放页型章节：页面上解不出音频算已失效；取页回 404 也算；网络错误可重试。
    @Test func pageResolverErrorsAreClassified() {
        let chapterURL: URL = URL(string: "https://leting8.example/play/20928/1.html")!
        #expect(SiteBookAudioHTTPClient.failureKind(resolverError: BookPublicationContentError.unexpectedContent(chapterURL: chapterURL)) == .gone)
        #expect(SiteBookAudioHTTPClient.failureKind(resolverError: RuleExecutionError.httpStatus(url: chapterURL.absoluteString, statusCode: 404)) == .gone)
        #expect(SiteBookAudioHTTPClient.failureKind(resolverError: RuleExecutionError.httpStatus(url: chapterURL.absoluteString, statusCode: 503)) == .unavailable)
        #expect(SiteBookAudioHTTPClient.failureKind(resolverError: URLError(.timedOut)) == .unavailable)
    }

    /// AVPlayer 换 Range、换集时取消请求，不算失败。
    @Test func cancelledRequestIsNotAFailure() {
        #expect(SiteBookAudioHTTPClient.failureKind(httpError: .cancelled) == nil)
        #expect(SiteBookAudioHTTPClient.failureKind(httpError: .timeout(nil)) == .unavailable)
    }
}

struct AudiobookPlaybackSpeedTests {
    @Test func storedSpeedDefaultsToNormalAndRoundTrips() throws {
        let suiteName: String = "AudiobookPlaybackSpeedTests-\(UUID().uuidString)"
        let defaults: UserDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        #expect(AudiobookPlaybackSpeed.stored(in: defaults) == .normal)
        AudiobookPlaybackSpeed.faster.store(in: defaults)
        #expect(AudiobookPlaybackSpeed.stored(in: defaults) == .faster)
        defaults.set(3.0, forKey: AudiobookPlaybackSpeed.defaultsKey)
        #expect(AudiobookPlaybackSpeed.stored(in: defaults) == .normal)
    }

    @Test func labelsAreFixedAcrossLanguages() {
        #expect(AudiobookPlaybackSpeed.allCases.map(\.label) == ["0.75×", "1.0×", "1.25×", "1.5×", "2.0×"])
    }
}

struct AudiobookCoverColorTests {
    /// 上半红、下半蓝的封面：取出的主色里有红也有蓝，背景调色板取得出来。
    @Test func dominantColorsFindTheCoverHues() throws {
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let image: UIImage = renderer.image { context in
            UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            UIColor(red: 0.1, green: 0.2, blue: 0.85, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 20, width: 40, height: 20))
        }
        let colors: [AudiobookCoverColor] = try #require(AudiobookCoverColor.dominantColors(of: image))
        #expect(colors.isEmpty == false)
        #expect(colors.contains { $0.hue < 0.05 || $0.hue > 0.95 })
        #expect(colors.contains { $0.hue > 0.6 && $0.hue < 0.7 })
        #expect(AudiobookBackdropPalette(image: image) != nil)
    }

    /// 色块取最鲜艳的簇：灰色不提饱和度，有色的提到 1.5 倍。
    @Test func vividColorsAreBoostedButGraysAreNot() {
        let gray: AudiobookCoverColor = AudiobookCoverColor(hue: 0.6, saturation: 0.05, brightness: 0.7)
        let khaki: AudiobookCoverColor = AudiobookCoverColor(hue: 0.13, saturation: 0.4, brightness: 0.7)
        #expect(gray.boosted() == gray)
        #expect(abs(khaki.boosted().saturation - 0.6) < 0.0001)
        #expect(khaki.vividness > gray.vividness)
    }

    /// 色块亮度压在 0.32–0.55、饱和度不超过上限；底色压到 0.11。
    @Test func adjustmentsClampBrightnessAndSaturation() {
        let bright: AudiobookCoverColor = AudiobookCoverColor(hue: 0.3, saturation: 0.95, brightness: 0.98)
        let blob: AudiobookCoverColor = bright.adjusted(saturationCap: 0.6, brightnessRange: 0.32...0.55)
        #expect(blob.brightness == 0.55)
        #expect(blob.saturation == 0.6)
        let dark: AudiobookCoverColor = AudiobookCoverColor(hue: 0.3, saturation: 0.2, brightness: 0.05)
        #expect(dark.adjusted(saturationCap: 0.6, brightnessRange: 0.32...0.55).brightness == 0.32)
        #expect(bright.adjusted(saturationCap: 0.55, brightness: 0.11).brightness == 0.11)
    }
}
