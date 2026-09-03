import Foundation

public struct SourceDetectionLexicon: Hashable, Sendable {
    public enum Language: String, CaseIterable, Hashable {
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        case japanese = "ja"

        public static func preferred(from preferredLanguages: [String] = Locale.preferredLanguages) -> Language? {
            for identifier in preferredLanguages {
                let normalized: String = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
                if normalized.hasPrefix("zh-hans") || normalized == "zh" || normalized.hasPrefix("zh-cn") {
                    return .simplifiedChinese
                }

                if normalized.hasPrefix("ja") {
                    return .japanese
                }

                if normalized.hasPrefix("en") {
                    return .english
                }
            }

            return nil
        }
    }

    public enum Category: String, Codable, Hashable, Sendable {
        case advertising
        case popupOrOverlay
        case tracking
        case accountNavigation
        case externalPromotion
        case playbackStructure
        case webViewShell
        case directMedia
        case macCMSPayload
        case macCMSRoute
        case macCMSTemplate
        case macCMSWeak
        case genericListCard
        case genericSupporting
        case iframePlayback
        case pluginRestriction
        case captchaRestriction
        case signingRestriction
        case encryptedPlaybackRestriction
        case wasmRestriction
        case sessionRestriction
        case privateAPIRestriction
        case payRestriction
        case accountRestriction
        case navigationReject
        case episodeGroupNoise
        case feedStructure
        case comicStructure
    }

    private let markersByCategory: [Category: [String]]

    public static let `default`: SourceDetectionLexicon = SourceDetectionLexicon.load()

    /// 中文注释：词典 JSON 随本框架发布，因此按框架自身 bundle 定位，不能用 App 的 main bundle。
    public static let resourceBundle: Bundle = Bundle(for: SourceDetectionLexiconBundleToken.self)

    public init(markersByCategory: [Category: [String]]) {
        self.markersByCategory = markersByCategory.mapValues(Self.normalizedMarkers)
    }

    public static func load(
        language: Language? = Language.preferred(),
        bundle: Bundle = SourceDetectionLexicon.resourceBundle
    ) -> SourceDetectionLexicon {
        var merged: [Category: [String]] = Self.markers(
            resourceName: "SourceDetectionLexicon.base",
            bundle: bundle
        ) ?? Self.structuralFallbackMarkers

        if let language {
            let languageMarkers: [Category: [String]] = Self.markers(
                resourceName: "SourceDetectionLexicon.\(language.rawValue)",
                bundle: bundle
            ) ?? [:]

            merged = Self.merging(base: merged, overlay: languageMarkers)
        }

        return SourceDetectionLexicon(markersByCategory: merged)
    }

    public func markers(for category: Category) -> [String] {
        return self.markersByCategory[category] ?? []
    }

    public func containsMarker(in text: String, category: Category) -> Bool {
        let normalizedText: String = text.lowercased()
        return self.markers(for: category).contains { marker in
            normalizedText.contains(marker.lowercased())
        }
    }

    private static func markers(resourceName: String, bundle: Bundle) -> [Category: [String]]? {
        guard let url: URL = bundle.url(forResource: resourceName, withExtension: "json"),
              let data: Data = try? Data(contentsOf: url),
              let payload: [String: [String]] = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return nil
        }

        var markers: [Category: [String]] = [:]
        for (key, values) in payload {
            guard let category: Category = Category(rawValue: key) else {
                continue
            }

            markers[category] = Self.normalizedMarkers(values)
        }

        return markers
    }

    private static func merging(
        base: [Category: [String]],
        overlay: [Category: [String]]
    ) -> [Category: [String]] {
        var result: [Category: [String]] = base
        for (category, markers) in overlay {
            result[category] = Self.normalizedMarkers((result[category] ?? []) + markers)
        }

        return result
    }

    private static func normalizedMarkers(_ markers: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for marker in markers {
            let trimmed: String = marker.trimmingCharacters(in: .whitespacesAndNewlines)
            let key: String = trimmed.lowercased()
            guard trimmed.isEmpty == false,
                  seen.contains(key) == false else {
                continue
            }

            seen.insert(key)
            result.append(trimmed)
        }

        return result
    }

    // Keep the built-in fallback intentionally structural-only; language-specific semantic markers live in JSON.
    private static let structuralFallbackMarkers: [Category: [String]] = [
        .directMedia: [
            ".m3u8",
            ".mp4",
            "<video",
            "<source",
            "application/vnd.apple.mpegurl",
            "video/mp4"
        ],
        .iframePlayback: [
            "embed/",
            "/embed",
            "player",
            "allowfullscreen",
            "html5player"
        ],
        .playbackStructure: [
            "player",
            "play",
            "embed",
            "iframe",
            "video",
            "m3u8",
            "mp4"
        ],
        .webViewShell: [
            "id=\"app\"",
            "id='app'",
            "data-reactroot",
            "__nuxt",
            "__next"
        ],
        .feedStructure: [
            "rss",
            "atom",
            "xml",
            "json"
        ]
    ]
}

private final class SourceDetectionLexiconBundleToken {}
