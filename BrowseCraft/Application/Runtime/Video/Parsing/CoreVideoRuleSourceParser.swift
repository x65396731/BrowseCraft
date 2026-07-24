import Foundation
import BrowseCraftCore

// 中文注释：Video V2 的 DOM 解释全部由 BrowseCraftCore 执行；App 适配器只把
// Core 输出映射到 Loader 的临时内部结果，不持有 SwiftSoup 或 selector 逻辑。
final class CoreVideoRuleSourceParser: VideoRuleSourceParsingService {
    func parseList(
        html: String,
        pageURL: URL,
        rule: VideoListRule
    ) throws -> VideoRuleParsedList {
        let output = try BrowseCraftCore.DefaultVideoListRuleParser().parseList(
            BrowseCraftCore.VideoListParsingInput(
                document: Self.document(html: html, pageURL: pageURL),
                rule: rule,
                runtimeContext: Self.context(
                    ruleID: rule.id,
                    operation: .list
                )
            )
        )
        let items = output.items.compactMap { item -> VideoRuleParsedListItem? in
            guard let detailURL = item.detailURL else {
                return nil
            }
            return VideoRuleParsedListItem(
                idCode: item.idCode,
                title: item.title,
                detailURL: detailURL,
                coverURL: item.coverURL,
                latestText: item.latestText
            )
        }
        return VideoRuleParsedList(
            items: items,
            candidateCount: output.diagnostics.candidateSummary?
                .totalCandidates ?? items.count,
            droppedCount: output.diagnostics.candidateSummary?
                .warningCount ?? 0
        )
    }

    func parseDetail(
        html: String,
        pageURL: URL,
        rule: VideoDetailRule
    ) throws -> VideoRuleParsedDetail {
        let output = try BrowseCraftCore.DefaultVideoDetailRuleParser()
            .parseDetail(
                BrowseCraftCore.VideoDetailParsingInput(
                    document: Self.document(html: html, pageURL: pageURL),
                    rule: rule,
                    runtimeContext: Self.context(
                        ruleID: rule.id,
                        operation: .detail
                    )
                )
            )
        let attributes = output.metadata.attributes.enumerated().map { offset, attribute in
            let matchingRule = rule.fields?.metadata?.first { field in
                Self.nonEmpty(field.label) == attribute.label
            }
            return VideoRuleParsedDetailAttribute(
                id: matchingRule?.id ?? "metadata-\(offset)",
                label: attribute.label,
                value: attribute.value
            )
        }
        return VideoRuleParsedDetail(
            metadata: VideoRuleParsedDetailMetadata(
                idCode: output.metadata.idCode,
                title: output.metadata.title,
                coverURL: output.metadata.coverURL,
                description: output.metadata.description,
                attributes: attributes
            ),
            readyMatched: output.readyMatched
        )
    }

    func parseEpisodes(
        html: String,
        pageURL: URL,
        rule: VideoEpisodeRule
    ) throws -> VideoRuleParsedEpisodes {
        let output = try BrowseCraftCore.DefaultVideoEpisodeRuleParser()
            .parseEpisodes(
                BrowseCraftCore.VideoEpisodeParsingInput(
                    document: Self.document(html: html, pageURL: pageURL),
                    rule: rule,
                    runtimeContext: Self.context(
                        ruleID: rule.id,
                        operation: .detail
                    )
                )
            )
        return Self.episodes(from: output)
    }

    func parsePlayback(
        html: String,
        pageURL: URL,
        rule: VideoPlaybackRule
    ) throws -> VideoRuleParsedPlayback {
        let output = try BrowseCraftCore.DefaultVideoPlaybackRuleParser()
            .parsePlayback(
                BrowseCraftCore.VideoPlaybackParsingInput(
                    document: Self.document(html: html, pageURL: pageURL),
                    rule: rule,
                    runtimeContext: Self.context(
                        ruleID: rule.id,
                        operation: .playback
                    )
                )
            )
        return VideoRuleParsedPlayback(
            mediaURLs: output.mediaURLs,
            mediaCandidateCount: output.mediaCandidateCount,
            invalidMediaURLCount: output.invalidMediaURLCount,
            iframeURLs: output.iframeURLs,
            iframeCandidateCount: output.iframeCandidateCount,
            invalidIframeURLCount: output.invalidIframeURLCount,
            readyMatched: output.readyMatched
        )
    }

    static func episodes(
        from output: BrowseCraftCore.VideoEpisodeParsingResult
    ) -> VideoRuleParsedEpisodes {
        VideoRuleParsedEpisodes(
            groups: output.groups.map { group in
                VideoRuleParsedEpisodeGroup(
                    idCode: group.idCode,
                    title: group.title,
                    episodes: group.episodes.map { episode in
                        VideoRuleParsedEpisode(
                            idCode: episode.idCode,
                            title: episode.title,
                            playURL: episode.playURL,
                            order: episode.order,
                            isRestricted: episode.isRestricted,
                            isPaid: episode.isPaid
                        )
                    },
                    candidateCount: group.candidateCount,
                    droppedCount: group.droppedCount
                )
            },
            readyMatched: output.readyMatched,
            candidateCount: output.candidateCount,
            droppedCount: output.droppedCount
        )
    }

    private static func document(
        html: String,
        pageURL: URL
    ) -> SourceContentDocument {
        SourceContentDocument(
            text: html,
            finalURL: pageURL,
            format: .html,
            mediaType: "text/html"
        )
    }

    private static func context(
        ruleID: String,
        operation: SourceRuntimeOperation
    ) -> SourceRuntimeContext {
        SourceRuntimeContext(
            sourceID: "video.v2.parser",
            pageID: nil,
            tabID: nil,
            ruleID: ruleID,
            requestOverride: nil,
            debugMode: false,
            operation: operation
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
