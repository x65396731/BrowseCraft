import Foundation

// 中文注释：规则候选分析按页面阶段区分输出。
enum RuleAnalysisStage: String, Hashable {
    case list
    case search
    case detail
    case reader
}
