import Foundation

/// 去首尾空白后非空才算有值；规则给的标题、简介、元数据常是空串或只有换行（2026-10-11 复审「跨页复制」收敛，此前五个 ViewModel / 视图各一份 `nonEmpty`）。
enum TrimmedText {
    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed: String = text?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }
}
