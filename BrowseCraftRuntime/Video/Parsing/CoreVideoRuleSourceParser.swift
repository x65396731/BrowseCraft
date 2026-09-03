import Foundation
import BrowseCraftCore

// 中文注释：Video V2 的 DOM 解释全部由 BrowseCraftCore 执行；App 适配器只把
// Core 输出映射到 Loader 的临时内部结果，不持有 SwiftSoup 或 selector 逻辑。
public final class CoreVideoRuleSourceParser: VideoRuleSourceParsingService {
    public init() {}

    public func parseList(
        html: String,
        pageURL: URL,
        rule: VideoListRule
    ) throws -> VideoRuleParsedList {
        let document: SourceContentDocument = Self.document(html: html, pageURL: pageURL)
        let runtimeContext: SourceRuntimeContext = Self.context(
            ruleID: rule.id,
            operation: .list
        )
        let output: SourceListOutput = try self.parseListOutput(
            document: document,
            rule: rule,
            runtimeContext: runtimeContext
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

    private func parseListOutput(
        document: SourceContentDocument,
        rule: VideoListRule,
        runtimeContext: SourceRuntimeContext
    ) throws -> SourceListOutput {
        let parser = BrowseCraftCore.DefaultVideoListRuleParser()
        do {
            return try parser.parseList(
                BrowseCraftCore.VideoListParsingInput(
                    document: document,
                    rule: rule,
                    runtimeContext: runtimeContext
                )
            )
        } catch let error as SourceParsingError {
            guard self.shouldRetryWithoutReady(error: error, rule: rule) else {
                throw error
            }

            var fallbackRule: VideoListRule = rule
            fallbackRule.ready = nil
            let fallbackOutput: SourceListOutput = try parser.parseList(
                BrowseCraftCore.VideoListParsingInput(
                    document: document,
                    rule: fallbackRule,
                    runtimeContext: runtimeContext
                )
            )
            let candidateCount: Int = fallbackOutput.diagnostics.candidateSummary?
                .totalCandidates ?? fallbackOutput.items.count
            if candidateCount > 0 {
                return fallbackOutput
            }
            throw error
        }
    }

    public func parseDetail(
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

    public func parseEpisodes(
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

    public func parsePlayback(
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
            mediaCandidates: output.mediaCandidates.map { candidate in
                VideoRuleParsedMediaCandidate(
                    ruleID: candidate.ruleID,
                    title: candidate.title,
                    url: candidate.url,
                    kind: candidate.kind
                )
            },
            mediaURLs: output.mediaURLs,
            mediaCandidateCount: output.mediaCandidateCount,
            invalidMediaURLCount: output.invalidMediaURLCount,
            iframeURLs: output.iframeURLs,
            iframeCandidateCount: output.iframeCandidateCount,
            invalidIframeURLCount: output.invalidIframeURLCount,
            readyMatched: output.readyMatched
        )
    }

    public static func episodes(
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

    private func shouldRetryWithoutReady(
        error: SourceParsingError,
        rule: VideoListRule
    ) -> Bool {
        guard rule.ready != nil else {
            return false
        }
        guard case .responseContract(let reason) = error else {
            return false
        }
        return reason == "Video V2 list readiness selector produced no output for rule \(rule.id)."
    }
}
