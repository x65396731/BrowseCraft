import Combine
import Foundation

// 中文注释：SourceSelectionStore 是应用级状态服务，只负责记录当前选中的内容源。
final class SourceSelectionStore: ObservableObject {
    @Published var selectedSourceID: String?
}
