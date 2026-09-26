import Foundation
import XCTest
@testable import BrowseCraft

/// `BC-ACQ-062`：地区取值的单一定义点（fwq 设计书 §24）。
///
/// 反向植入这四处之一，本文件必须失败：
///   ① 把 `SafariRequestHeaderProvider` 的语言头改回写死的常量；
///   ② 去掉 BCP-47 前缀降级链，直接发 `Locale.preferredLanguages`；
///   ③ 让设备给不出标签时编一个地区出来，而不是回落到「未指定」；
///   ④ 把不合 `Accept-Language` 文法的标签照发给服务端（服务端会 400）。
final class DeviceAcceptLanguageTests: XCTestCase {
    func testPrefixChainTakesOnlyTruePrefixes() throws {
        /// 只降级、不猜地区——把「繁中」映射成 zh-TW 那种是词表判据。
        XCTAssertEqual(
            DeviceAcceptLanguage.prefixChain("zh-Hant-JP"),
            ["zh-Hant-JP", "zh-Hant", "zh"]
        )
        XCTAssertEqual(DeviceAcceptLanguage.prefixChain("en-US"), ["en-US", "en"])
        XCTAssertEqual(DeviceAcceptLanguage.prefixChain("ja"), ["ja"])
    }

    func testRealDeviceCaseGetsMatchableTags() throws {
        /// 2026-09-19 真机日志的原始输入：设备语言繁中/简中/英文，地区日本。
        /// 修正前发出的是 `zh-Hant-JP,zh-Hans-JP;q=0.9,en-JP;q=0.8,ja-JP;q=0.7`——
        /// 整串没有一条能被按语言匹配的站认出来。
        let value: String = try XCTUnwrap(
            DeviceAcceptLanguage(
                preferredLanguages: ["zh-Hant-JP", "zh-Hans-JP", "en-JP", "ja-JP"]
            ).value()
        )
        XCTAssertTrue(value.hasPrefix("zh-Hant-JP,"), value)
        // 站点真正会匹配的那几级必须在串里。
        XCTAssertTrue(value.contains("zh-Hant;q="), value)
        XCTAssertTrue(value.contains("zh;q="), value)
        XCTAssertTrue(value.contains("zh-Hans;q="), value)
        XCTAssertTrue(value.contains("en;q="), value)
    }

    func testPrimaryTagCarriesNoWeightAndTheRestDescend() throws {
        let value: String? = DeviceAcceptLanguage(
            preferredLanguages: ["zh-Hant-TW", "en-US"]
        ).value()
        XCTAssertEqual(value, "zh-Hant-TW,zh-Hant;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6")
    }

    func testDeduplicatesAcrossChains() throws {
        /// `zh-Hant-JP` 与 `zh-Hans-JP` 的链都以 `zh` 收尾，`zh` 只能出现一次。
        let value: String = try XCTUnwrap(
            DeviceAcceptLanguage(
                preferredLanguages: ["zh-Hant-JP", "zh-Hans-JP"]
            ).value()
        )
        let tags: [String] = value.components(separatedBy: ",").map { entry in
            String(entry.split(separator: ";").first ?? "")
        }
        XCTAssertEqual(Set(tags).count, tags.count, value)
        XCTAssertEqual(tags.filter { $0 == "zh" }.count, 1, value)
    }

    func testStaysWithinTheServerLengthLimit() throws {
        let value: String = try XCTUnwrap(
            DeviceAcceptLanguage(
                preferredLanguages: (0..<12).map { "zh-Hant\($0)-JP" }
            ).value()
        )
        XCTAssertLessThanOrEqual(value.count, DeviceAcceptLanguage.maximumLength)
        // 按整条截断，不留半截标签。
        XCTAssertFalse(value.hasSuffix(","), value)
        XCTAssertFalse(value.hasSuffix(";"), value)
        XCTAssertFalse(value.contains(",;"), value)
    }

    func testDropsTagsOutsideTheAcceptLanguageGrammar() throws {
        /// 服务端对该字段是严格白名单、不合即 400；宁可在客户端丢掉，也不要发出去换一个 400。
        let value: String? = DeviceAcceptLanguage(
            preferredLanguages: ["zh-CN\r\nCookie: a=1", "  ", "en-US"]
        ).value()
        XCTAssertEqual(value, "en-US,en;q=0.9")
    }

    func testNoUsableTagMeansNoValueRatherThanAnInventedLocale() throws {
        /// 宁可不发——服务端字段可选，不发时引擎退回它自己的默认值。
        XCTAssertNil(DeviceAcceptLanguage(preferredLanguages: []).value())
        XCTAssertNil(DeviceAcceptLanguage(preferredLanguages: ["", "  "]).value())
    }

    func testProviderHeaderUsesTheDeviceLocaleNotAHardCodedOne() throws {
        let provider = SafariRequestHeaderProvider(
            deviceAcceptLanguage: DeviceAcceptLanguage(
                preferredLanguages: ["zh-Hant-TW"]
            )
        )
        let headers: [String: String] = provider.defaultHeaders(
            for: try XCTUnwrap(URL(string: "https://example.com/")),
            referer: nil,
            includeOrigin: false
        )
        XCTAssertEqual(headers["Accept-Language"], "zh-Hant-TW,zh-Hant;q=0.9,zh;q=0.8")
        XCTAssertEqual(provider.acceptLanguage, headers["Accept-Language"])
        XCTAssertNotEqual(
            headers["Accept-Language"],
            SafariRequestHeaderProvider.unspecifiedLocaleAcceptLanguage
        )
    }

    func testProviderFallsBackToTheUnspecifiedLocaleValue() throws {
        let provider = SafariRequestHeaderProvider(
            deviceAcceptLanguage: DeviceAcceptLanguage(preferredLanguages: [])
        )
        XCTAssertEqual(
            provider.acceptLanguage,
            SafariRequestHeaderProvider.unspecifiedLocaleAcceptLanguage
        )
    }
}
