import Foundation
import BrowseCraftCore

/// 中文注释：保留 App 既有边界名称，确定性的 DOM 快照解析委托给 BrowseCraftCore。
struct CoreHTMLDiscoveryParser: HTMLDiscoveryParsingService {
    private let analyzer: any BrowseCraftCore.SourceDiscoveryAnalyzing

    init(
        analyzer: any BrowseCraftCore.SourceDiscoveryAnalyzing =
            BrowseCraftCore.DefaultSourceDiscoveryAnalyzer()
    ) {
        self.analyzer = analyzer
    }

    func parseAnchors(html: String, pageURL: URL) throws -> [HTMLDiscoveryAnchorSnapshot] {
        let analysis = try self.analyzer.analyze(
            BrowseCraftCore.SourceDiscoveryAnalysisInput(
                document: BrowseCraftCore.SourceContentDocument(
                    data: Data(html.utf8),
                    finalURL: pageURL,
                    format: .html,
                    mediaType: "text/html"
                ),
                sourceID: pageURL.host ?? pageURL.absoluteString,
                sourceName: pageURL.host ?? pageURL.absoluteString,
                operation: .debug,
                candidateScope: .anchorsOnly,
                maximumAncestorDepth: 12
            )
        )
        return analysis.anchors
    }
}
