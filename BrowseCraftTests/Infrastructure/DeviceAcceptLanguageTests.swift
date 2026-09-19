import Foundation
import XCTest
@testable import BrowseCraft

/// `BC-ACQ-062`：地区取值的单一定义点（fwq 设计书 §24）。
///
/// 反向植入这三处之一，本文件必须失败：
///   ① 把 `ChromeRequestHeaderProvider` 的语言头改回写死的常量；
///   ② 让设备给不出标签时编一个地区出来，而不是回落到「未指定」；
///   ③ 把不合 `Accept-Language` 文法的标签照发给服务端（服务端会 400）。
final class DeviceAcceptLanguageTests: XCTestCase {
    func testPrimaryTagCarriesNoWeightAndTheRestDescend() throws {
        let value: String? = DeviceAcceptLanguage(
            preferredLanguages: ["zh-Hant-TW", "en-US", "ja-JP"]
        ).value()
        XCTAssertEqual(value, "zh-Hant-TW,en-US;q=0.9,ja-JP;q=0.8")
    }

    func testDeduplicatesAndCapsTheTagCount() throws {
        let value: String = try XCTUnwrap(
            DeviceAcceptLanguage(
                preferredLanguages: ["en-US", "EN-us", "fr-FR", "de-DE", "ja-JP", "ko-KR"]
            ).value()
        )
        // 去重后截到 4 个：en-US / fr-FR / de-DE / ja-JP。
        XCTAssertEqual(value.components(separatedBy: ",").count, 4)
        XCTAssertTrue(value.hasPrefix("en-US,"), value)
        XCTAssertFalse(value.contains("ko-KR"), value)
    }

    func testDropsTagsOutsideTheAcceptLanguageGrammar() throws {
        /// 服务端对该字段是严格白名单、不合即 400；宁可在客户端丢掉，也不要发出去换一个 400。
        let value: String? = DeviceAcceptLanguage(
            preferredLanguages: ["zh-CN\r\nCookie: a=1", "  ", "en-US"]
        ).value()
        XCTAssertEqual(value, "en-US")
    }

    func testNoUsableTagMeansNoValueRatherThanAnInventedLocale() throws {
        /// 宁可不发——服务端字段可选，不发时引擎退回它自己的默认值。
        XCTAssertNil(DeviceAcceptLanguage(preferredLanguages: []).value())
        XCTAssertNil(DeviceAcceptLanguage(preferredLanguages: ["", "  "]).value())
    }

    func testProviderHeaderUsesTheDeviceLocaleNotAHardCodedOne() throws {
        let provider = ChromeRequestHeaderProvider(
            deviceAcceptLanguage: DeviceAcceptLanguage(
                preferredLanguages: ["zh-Hant-TW", "en-US"]
            )
        )
        let headers: [String: String] = provider.defaultHeaders(
            for: try XCTUnwrap(URL(string: "https://example.com/")),
            referer: nil,
            includeOrigin: false
        )
        XCTAssertEqual(headers["Accept-Language"], "zh-Hant-TW,en-US;q=0.9")
        XCTAssertEqual(provider.acceptLanguage, "zh-Hant-TW,en-US;q=0.9")
        XCTAssertNotEqual(
            headers["Accept-Language"],
            ChromeRequestHeaderProvider.unspecifiedLocaleAcceptLanguage
        )
    }

    func testProviderFallsBackToTheUnspecifiedLocaleValue() throws {
        let provider = ChromeRequestHeaderProvider(
            deviceAcceptLanguage: DeviceAcceptLanguage(preferredLanguages: [])
        )
        XCTAssertEqual(
            provider.acceptLanguage,
            ChromeRequestHeaderProvider.unspecifiedLocaleAcceptLanguage
        )
    }
}
