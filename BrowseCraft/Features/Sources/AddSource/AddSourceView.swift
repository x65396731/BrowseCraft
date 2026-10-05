import BrowseCraftDomain
import Foundation
import SwiftUI

// 中文注释：AddSourceView.swift 是添加来源的入口页（`docs/design/Add-Source-Page-Redesign-Design.md`）：
// 选类型 → 合格入口页引导屏（首次）→ 网址输入页，三屏在同一层 sheet 里依次出现，不叠第二层。

/// 添加来源页：自绘大标题、一句说明、三张可点的类型横幅、「接下来」三行、coin 与登录提示、目录入口卡。
///
/// 中文注释：选了类型之后**不是再弹一层 sheet**，而是把这一层的内容换成 `EntryPageGuideFlowView`——
/// 页面设计索引的约定是两个 sheet 不同时呈现。输入页的 `onDisappear` 绑着 `onFinished()`（三种关法一个落点），
/// 条件渲染下它只在整个 sheet 关闭时 disappear，那条纪律原样成立。选类型页自己没有 `onDisappear`，
/// 被换掉时不会触发任何关闭。
@MainActor
struct AddSourceView: View {
    @Bindable var viewModel: SourcesViewModel
    /// 「从规则目录挑一个」：宿主在本页收起后打开目录；为 nil 时不显示这张卡（从目录页进来的那次）。
    var openCatalog: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: RuleGenerationSourceKind?

    /// 中文注释：三张类型卡的顺序与收藏页、历史页的筛选一致（视频、漫画、书籍）。
    private static let kinds: [RuleGenerationSourceKind] = [.video, .comic, .book]

    var body: some View {
        Group {
            if let kind: RuleGenerationSourceKind = self.selectedKind {
                EntryPageGuideFlowView(
                    viewModel: self.viewModel,
                    sourceKind: kind,
                    onFinished: self.returnToSources
                )
                .transition(.push(from: .trailing))
            } else {
                self.kindPicker
                    .transition(.push(from: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: self.selectedKind)
    }

    /// 中文注释：预检页无论怎么结束（提交成功自动返回、按「关闭」、下滑关掉）都回到来源页，
    /// 三种关法一个落点。提交成功的那次用户已经拿到任务回执，规则生成完会自己出现在目录里，
    /// 没有留在这一屏继续点的事。自动返回已经收掉这一层时，后到的那次 `dismiss()` 是空操作。
    private func returnToSources() {
        self.dismiss()
    }

    // MARK: - 选类型

    private var kindPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 中文注释：标题按设计稿自己画在内容里，与来源页、目录页同一做法；系统导航栏只留左上「关闭」。
                    Text(NSLocalizedString("Add Source", comment: ""))
                        .font(.largeTitle.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Text(NSLocalizedString("add_source_intro", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(Self.kinds, id: \.self) { kind in
                            self.kindCard(for: kind)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    self.nextStepsGroup

                    if let openCatalog: () -> Void = self.openCatalog {
                        SourcesEntryCardView(
                            title: NSLocalizedString("sources_empty_catalog_title", comment: ""),
                            message: NSLocalizedString("add_source_catalog_card_message", comment: ""),
                            systemImage: "sparkles",
                            iconForeground: CatalogPalette.settingsIcon,
                            iconBackground: CatalogPalette.settingsIconFill,
                            action: {
                                openCatalog()
                                self.dismiss()
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(CatalogPalette.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                }
            }
            .onAppear {
                CrashDiagnostics.shared.setScreen(.addSource)
                AppAnalytics.shared.logScreenView(.addSource)
            }
        }
    }

    /// 中文注释：类型卡就是规则目录页的类型横幅（固定深色底 + 现有插画），用户在目录页见过同一张图，
    /// 到这里一眼认出类型；不另出一批插画（2026-10-06 用户裁定沿用）。
    private func kindCard(for kind: RuleGenerationSourceKind) -> some View {
        Button {
            self.selectedKind = kind
        } label: {
            CatalogKindBannerView(
                style: CatalogKindStyle.of(Self.catalogKind(of: kind)),
                subtitle: NSLocalizedString(Self.exampleKey(for: kind), comment: ""),
                showsChevron: true
            )
        }
        .buttonStyle(AddSourceKindCardButtonStyle())
        .accessibilityAddTraits(.isButton)
    }

    private static func catalogKind(of kind: RuleGenerationSourceKind) -> CatalogSourceKind {
        switch kind {
        case .video:
            return .video
        case .comic:
            return .comic
        case .book:
            return .book
        }
    }

    private static func exampleKey(for kind: RuleGenerationSourceKind) -> String {
        switch kind {
        case .video:
            return "add_source_kind_example_video"
        case .comic:
            return "add_source_kind_example_comic"
        case .book:
            return "add_source_kind_example_book"
        }
    }

    // MARK: - 接下来

    /// 三行说明之后会怎样，行不可点；组下一行是 coin 与登录提示（只提示，不拦路）。
    private var nextStepsGroup: some View {
        SettingsCardGroup(
            title: NSLocalizedString("add_source_next_title", comment: ""),
            footer: self.coinFooter
        ) {
            self.nextStepRow(systemImage: "link", textKey: "add_source_next_step_url")
            SettingsRowSeparator()
            self.nextStepRow(systemImage: "checkmark.circle", textKey: "add_source_next_step_check")
            SettingsRowSeparator()
            self.nextStepRow(systemImage: "sparkles", textKey: "add_source_next_step_catalog")
        }
    }

    private func nextStepRow(systemImage: String, textKey: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CatalogPalette.settingsIcon)
                .frame(width: 32, height: 32)
                .background(CatalogPalette.settingsIconFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Text(NSLocalizedString(textKey, comment: ""))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    /// 中文注释：价格取服务端下发的普通档价格，不写死。已登录写价格与余额，余额还没同步到时只写价格，
    /// 未登录换成警示色的一句。没有钱包（测试替身）时整行不显示。
    private var coinFooter: String? {
        guard let wallet: CoinWalletStore = self.viewModel.coinWalletStore else {
            return nil
        }
        let price: Int = wallet.pricing.normal
        if wallet.isSignedIn == false {
            return String(format: NSLocalizedString("add_source_sign_in_required", comment: ""), price)
        }
        if let balance: Int = wallet.balance {
            return String(format: NSLocalizedString("add_source_coin_price_balance", comment: ""), price, balance)
        }
        return String(format: NSLocalizedString("add_source_coin_price", comment: ""), price)
    }
}

/// 类型卡按下时整张变暗。
private struct AddSourceKindCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.25 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
