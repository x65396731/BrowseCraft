import Foundation
@preconcurrency import GRDB

// 中文注释：引导阶段的数据库迁移失败要能定位。SQLite 的结果码是唯一有效线索
// （例如 SQLITE_CORRUPT、SQLITE_FULL、SQLITE_READONLY），只记结果码，不记 SQL 文本与绑定参数——
// 后者可能带用户内容。
extension DatabaseError: DiagnosticSummaryProviding {
    var diagnosticSummary: String {
        return "sqliteResultCode=\(self.resultCode.rawValue) extended=\(self.extendedResultCode.rawValue)"
    }
}
