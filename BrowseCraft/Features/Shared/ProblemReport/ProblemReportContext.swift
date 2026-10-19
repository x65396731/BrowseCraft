import BrowseCraftDomain
import Foundation

// 中文注释：报告面板需要的页面上下文（docs/design/Problem-Report-Design.md 第三、四、七节）。
// 库页与三种详情页各从自己的 ViewModel 拼一份；面板不认识具体页面。

/// 中文注释：选集行里的一集（话、章）。`url` 是目录里那一集的网址，报 content 时作为对象网址。
struct ProblemReportEpisode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// 从 1 起的序号（目录里的位置）。
    let index: Int
    let url: String?
}

/// 中文注释：一条线路的集列表；漫画与书只有一组，`title` 为 nil。
struct ProblemReportEpisodeLine: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let episodes: [ProblemReportEpisode]
}

struct ProblemReportContext: Identifiable {
    /// 中文注释：面板打开时生成一次，同时作为 `clientReportId`；「再试一次」沿用它。
    let id: UUID = UUID()
    let screen: DiagnosticScreen
    let source: Source
    let entry: ProblemReportEntry
    /// 对象卡上「来源名 · 页面名」的页面名部分，如「详情」「库页 · 动作分类」。
    let pageName: String
    /// 从失败态进来时当时显示的失败文案；常驻入口为 nil。
    let failureMessage: String?
    /// 库页为 `.list`，详情页为 `.detail`（面板里还可切到 `.content`）。
    let primaryScope: ProblemReportScope
    let targetURL: String?
    let targetTitle: String?
    let categoryKey: String?
    /// 报 list / detail 时快照取的失败点（合同第三节）。
    let primaryFailurePoints: Set<RuleFailurePoint>
    /// 报 content 时快照取的失败点；库页为空。
    let contentFailurePoints: Set<RuleFailurePoint>
    /// 选集行的目录；库页为空，详情页目录为空时也为空（「某一集的内容」不可选）。
    let lines: [ProblemReportEpisodeLine]
    /// 默认选中的线路与集：历史里的上次看到 / 读到，没有时为第一集。
    let defaultLineID: String?
    let defaultEpisodeID: String?
    /// 默认那一集是不是来自历史（行里写「上次看到」还是只写集名）。
    let defaultEpisodeIsFromHistory: Bool
    let isAudiobook: Bool

    var kind: DiagnosticSourceType {
        return self.source.diagnosticSourceType
    }

    var supportsContent: Bool {
        return self.primaryScope == .detail && self.lines.contains { $0.episodes.isEmpty == false }
    }

    /// 中文注释：漫画与书的目录只有一组，集的 id 用目录位置（网址可能重复，重复本身就是要报的问题之一）。
    static func singleLine(titlesAndURLs: [(title: String, url: String?)]) -> [ProblemReportEpisodeLine] {
        guard titlesAndURLs.isEmpty == false else {
            return []
        }
        let episodes: [ProblemReportEpisode] = titlesAndURLs.enumerated().map { offset, chapter in
            return ProblemReportEpisode(id: "\(offset)", title: chapter.title, index: offset + 1, url: chapter.url)
        }
        return [ProblemReportEpisodeLine(id: "chapters", title: nil, episodes: episodes)]
    }

    /// 中文注释：规则里的网址可能是相对路径或带 `{page}` 这类占位符；按来源站点地址补全，占位符转义后照原样留下。
    /// 补不全时为 nil（报告照样发，只是没有对象网址）。
    static func absoluteURL(_ raw: String?, baseURL: String) -> String? {
        guard let raw: String, raw.isEmpty == false else {
            return nil
        }
        let escaped: String = raw
            .replacingOccurrences(of: "{", with: "%7B")
            .replacingOccurrences(of: "}", with: "%7D")
        return URL(string: escaped, relativeTo: URL(string: baseURL))?.absoluteString
    }
}
