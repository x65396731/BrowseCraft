import Foundation
import Testing
@testable import BrowseCraft

struct SourceDetectionLexiconTests {
    @Test func loadsBaseAndRequestedLanguageOnly() {
        let english: SourceDetectionLexicon = SourceDetectionLexicon.load(language: .english)
        let simplifiedChinese: SourceDetectionLexicon = SourceDetectionLexicon.load(language: .simplifiedChinese)
        let japanese: SourceDetectionLexicon = SourceDetectionLexicon.load(language: .japanese)
        let baseOnly: SourceDetectionLexicon = SourceDetectionLexicon.load(language: nil)

        #expect(english.containsMarker(in: "<video src=\"sample.mp4\"></video>", category: .directMedia))
        #expect(english.containsMarker(in: "Login", category: .accountNavigation))
        #expect(english.containsMarker(in: "登录", category: .accountNavigation) == false)

        #expect(simplifiedChinese.containsMarker(in: "登录", category: .accountNavigation))
        #expect(simplifiedChinese.containsMarker(in: "ログイン", category: .accountNavigation) == false)

        #expect(japanese.containsMarker(in: "ログイン", category: .accountNavigation))
        #expect(japanese.containsMarker(in: "login", category: .accountNavigation) == false)

        #expect(baseOnly.containsMarker(in: "<iframe src=\"/embed/1\"></iframe>", category: .iframePlayback))
        #expect(baseOnly.containsMarker(in: "login", category: .accountNavigation) == false)
    }

    @Test func resolvesSupportedPreferredLanguages() {
        #expect(SourceDetectionLexicon.Language.preferred(from: ["zh-Hans-JP"]) == .simplifiedChinese)
        #expect(SourceDetectionLexicon.Language.preferred(from: ["ja-JP"]) == .japanese)
        #expect(SourceDetectionLexicon.Language.preferred(from: ["en-US"]) == .english)
        #expect(SourceDetectionLexicon.Language.preferred(from: ["ko-KR"]) == nil)
    }
}
