import BrowseCraftDomain
import Foundation
import SwiftUI

// 中文注释：`BC-PAGE-060` 定义的合格入口页两要素——①要有分页 ②必须是单 list family——
// 在 App 里此前一个字都没有：输入框只写「List 或分类页面 URL」，footer 写的是免责声明。
// 要素一预检根本不判（`AssessVideoGenerationInputUseCase` 只 observe + assess family），
// 用户要等服务端拒了才知道（2026-09-20 真机 gimy `/browse/3.html` 就是白等一次生成）。
// 条款自己留了这个位置：「不满足就拒绝并说明原因，由用户改用合格的入口地址
// （教程属产品侧，不在引擎内解决）」——这一屏就是那份教程。
//
// 它**不判定任何东西**：零网络、零登录、不改 `VideoGenerationInputPreflight.schemaVersion`。
// 服务端已有的同源判定端点（`POST /v1/rule-generations/entry-page-qualification`）
// 用户 2026-09-20 裁定不接线，本屏不改变那个决定。

enum EntryPageGuide {
    /// 中文注释：读过的版本号存这里。文案实质改版时把 `currentVersion` +1，老用户再看一次；
    /// 只改错别字不要动它，否则每个人都被多拦一屏。
    static let seenVersionKey: String = "entryPageGuideSeenVersion"
    /// 版本 2（2026-09-23，`BC-PAGE-061`）：分页说明改成「点到第 2 页地址会变」，并加一行「满足两条也可能生成不了」。
    /// 版本 3（2026-09-23）：首页入口不再支持；例子改成「全部」类列表页，其余内容靠搜索找到。
    static let currentVersion: Int = 3

    /// 中文注释：判定单独拿出来是为了可测——视图里的那份是 `private` 计算属性，测不到。
    /// 本次已经点过「我找到了这样的页面」就不再拦（`didAcknowledge`），
    /// 否则看存过的版本号：没看过、或看的是更早一版，都要再看一次。
    static func shouldPresent(seenVersion: Int, didAcknowledge: Bool) -> Bool {
        if didAcknowledge {
            return false
        }
        return seenVersion < Self.currentVersion
    }
}

/// 合格入口页引导屏。两种用法由 `primaryTitleKey` 与 `cancelAction` 区分：
/// 首屏（必过一次，带「取消」关掉整个流程）与回看（从输入页或失败行叠一层 sheet，只有「知道了」）。
struct EntryPageGuideView: View {
    /// 中文注释：失败行拉起这一屏时拿不到 kind——`/outcomes` 每条只有 jobId / entryURL /
    /// status / finishedAt / reason(Detail) / catalogSourceId（`BC-PREFLIGHT-056` 定死的字段），
    /// 没有 `sourceKind`。那种情况传 nil，举例退回 kind 中性的一句，不猜。
    let sourceKind: RuleGenerationSourceKind?
    let primaryTitleKey: String
    let primaryAction: () -> Void
    /// 中文注释：只有首屏形态有取消——回看形态是叠在别人上面的 sheet，关掉它用 `primaryAction` 就够。
    let cancelAction: (() -> Void)?

    var body: some View {
        Form {
            // 中文注释：引题图。她指着的那块卡片画的就是反例——几块区块拼起来、底部没有页码，
            // 与下面第一段「两条要求」说的是同一件事，所以它在最上面先把问题摆出来，
            // 而不是当装饰挂在某处。行背景清掉，让它读起来像 Form 的页眉而不是又一张分组卡片。
            Section {
                EmptyStateIconView(
                    systemImage: "questionmark.circle",
                    illustration: "EntryGuideUnsupportedPage",
                    height: 150
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                self.requirementRow(
                    systemImage: "list.number",
                    titleKey: "entry_guide_rule_pagination_title",
                    detailKey: "entry_guide_rule_pagination_detail"
                )
                self.requirementRow(
                    systemImage: "square.grid.2x2",
                    titleKey: "entry_guide_rule_single_list_title",
                    detailKey: "entry_guide_rule_single_list_detail"
                )
            } header: {
                Text(NSLocalizedString("entry_guide_requirements_title", comment: ""))
            } footer: {
                // 中文注释：`BC-PAGE-061` 全站直出拦的是作品页 / 阅读页里的额外接口与解密，
                // 用户在列表页上看不出来——先说一句，免得照着两条做了却被拒时觉得被骗。
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("entry_guide_subtitle", comment: ""))
                    Text(NSLocalizedString("entry_guide_requirements_caveat", comment: ""))
                }
            }

            Section(NSLocalizedString("entry_guide_examples_title", comment: "")) {
                Label {
                    Text(NSLocalizedString("entry_guide_example_bad", comment: ""))
                } icon: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                .listRowSeparatorAlignedToRowLeading()
                Label {
                    Text(NSLocalizedString(self.goodExampleKey, comment: ""))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .listRowSeparatorAlignedToRowLeading()
            }

            Section(NSLocalizedString("entry_guide_steps_title", comment: "")) {
                ForEach(Self.stepKeys, id: \.self) { key in
                    Text(NSLocalizedString(key, comment: ""))
                        .listRowSeparatorAlignedToRowLeading()
                }
            }

            Section {
                Button {
                    self.primaryAction()
                } label: {
                    Text(NSLocalizedString(self.primaryTitleKey, comment: ""))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(NSLocalizedString("entry_guide_title", comment: ""))
        .toolbar {
            if let cancelAction: () -> Void = self.cancelAction {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("video_preflight_close_button", comment: "")) {
                        cancelAction()
                    }
                }
            }
        }
    }

    private static let stepKeys: [String] = [
        "entry_guide_step_1",
        "entry_guide_step_2",
        "entry_guide_step_3"
    ]

    /// 中文注释：两条要素是 kind 中性的（`list_stage_flow` 三种 kind 共用同一道判据），
    /// 按 kind 变的只有这一句举例——视频/漫画说分类页，书说排行榜页。
    private var goodExampleKey: String {
        switch self.sourceKind {
        case .video:
            return "entry_guide_example_good_video"
        case .comic:
            return "entry_guide_example_good_comic"
        case .book:
            return "entry_guide_example_good_book"
        case nil:
            return "entry_guide_example_good_generic"
        }
    }

    @ViewBuilder
    private func requirementRow(
        systemImage: String,
        titleKey: String,
        detailKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(NSLocalizedString(titleKey, comment: ""), systemImage: systemImage)
            Text(NSLocalizedString(detailKey, comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowSeparatorAlignedToRowLeading()
    }
}

/// 添加来源选完 kind 之后的整条流程：先引导屏（首次必过），再预检输入页。
///
/// 中文注释：**刻意不做 push/pop 两页**，而是条件渲染两个各自带导航栈的分支。
/// 输入页的 `onDisappear` 绑着 `onFinished()`（三种关法一个落点，见 `AddSourceView`），
/// 一旦做成第二页，用户按系统返回键回引导屏就会触发 `onDisappear`，把整个 sheet 关掉。
/// 条件渲染下输入页只在 sheet 真被关闭时 disappear，那条纪律原样成立，
/// `VideoGenerationInputView` 的 body 一行都不用改。
/// 同理，输入页上的「怎样的页面能生成？」是**叠一层 sheet**，不是退回上一页。
struct EntryPageGuideFlowView: View {
    @Bindable var viewModel: SourcesViewModel
    let sourceKind: RuleGenerationSourceKind
    let onFinished: () -> Void

    @AppStorage(EntryPageGuide.seenVersionKey) private var seenVersion: Int = 0
    @State private var didAcknowledge: Bool = false

    var body: some View {
        if self.showsGuide {
            NavigationStack {
                EntryPageGuideView(
                    sourceKind: self.sourceKind,
                    primaryTitleKey: "entry_guide_continue_button",
                    primaryAction: self.acknowledge,
                    cancelAction: self.onFinished
                )
            }
        } else {
            // 中文注释：输入页自带 `NavigationStack`，这里不能再包一层，否则两个导航栏叠着出。
            VideoGenerationInputView(
                viewModel: self.viewModel,
                sourceKind: self.sourceKind,
                onFinished: self.onFinished
            )
        }
    }

    private var showsGuide: Bool {
        return EntryPageGuide.shouldPresent(
            seenVersion: self.seenVersion,
            didAcknowledge: self.didAcknowledge
        )
    }

    private func acknowledge() {
        self.seenVersion = EntryPageGuide.currentVersion
        self.didAcknowledge = true
    }
}
