import BrowseCraftDomain
import Foundation

// 中文注释：诊断枚举集中定义 Firebase 字段取值，避免散落字符串造成查询口径不一致。

enum DiagnosticScreen: String {
    case sourceList
    case addSource
    case sourceDetail
    case ruleEditor
    case library
    case favorite
    case history
    case settings
    case comicReader
    case videoDetail
    case videoPlayer
}

enum DiagnosticSourceType: String {
    case comic
    case video
    case book
    case unknown
}

enum DiagnosticRuleStage: String {
    case search
    case list
    case detail
    case chapter
    case reader
    case videoPlayback
    case unknown
}

enum DiagnosticSeverity: String {
    case info
    case warning
    case error
    case fatal
}

enum DiagnosticLogCategory: String {
    case network
    case parser
    case database
    case playback
    case sync
    case ui
    case unknown
}

extension Source {
    var diagnosticSourceType: DiagnosticSourceType {
        switch self.configuration.kind {
        case .comic:
            return .comic
        case .video:
            return .video
        case .plugin:
            return .unknown
        case .book:
            return .book
        }
    }
}

/// 中文注释：诊断上报只需要区分「网络类」与「解析类」两个桶。判定规则错误属于哪一桶要认
/// `RuleExecutionError`，那是 Application 的分类器的职责；Shared 只接收已判定的结果，
/// 因此本枚举是纯取值、不含任何判定逻辑。（2026-09-18 收敛边界豁免时引入。）
enum DiagnosticFailureKind: String {
    case network
    case parse
}
