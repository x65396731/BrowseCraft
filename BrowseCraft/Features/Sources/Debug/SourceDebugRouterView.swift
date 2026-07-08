import Foundation
import SwiftUI

// 中文注释：SourceDebugRouterView 只负责按 runtime 分发，不承载具体调试逻辑。
struct SourceDebugRouterView: View {
    @ObservedObject var viewModel: SourcesViewModel
    let kind: RuntimeSourceImportKind
    let entryURL: String
    let sourceName: String?
    let videoConfiguration: ManualVideoSourceConfigurationDraft?
    @Binding var ruleJSON: String

    var body: some View {
        switch self.kind {
        case .rss:
            RSSSourceDebugView(
                viewModel: self.viewModel,
                entryURL: self.entryURL
            )
        case .comic:
            RuleSourceDebugView(
                viewModel: self.viewModel,
                entryURL: self.entryURL,
                sourceName: self.sourceName,
                ruleJSON: self.$ruleJSON
            )
        case .video:
            VideoSourceDebugView(
                viewModel: self.viewModel,
                entryURL: self.entryURL,
                sourceName: self.sourceName,
                configuration: self.videoConfiguration ?? ManualVideoSourceConfigurationDraft(
                    adapter: .genericHTML,
                    entryKind: .play
                )
            )
        }
    }
}
