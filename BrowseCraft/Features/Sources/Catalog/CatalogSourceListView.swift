import SwiftUI
import BrowseCraftDomain

/// 规则目录页（`docs/design/Catalog-Page-Redesign-Design.md` 方案 A）：顶部分段切换「推荐 / 我的生成」。
/// 推荐 = 公共目录按类型分区、横滑卡片；我的生成 = 成功规则与失败记录合并的时间线，按天分组。
struct CatalogSourceListView: View {
    enum Tab: Hashable {
        case recommended
        case personal
    }

    @Bindable var viewModel: SourcesViewModel
    /// 我的生成空状态里「去添加来源」：宿主在目录页关闭后打开添加来源；为 nil 时不显示该按钮。
    var openAddSource: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// 中文注释：打开时「我的生成」有条目就落在「我的生成」，否则「推荐」（合同第 2.1 节）。
    /// 条目数要等首次拉取回来才准，所以 `.task` 拉完再按同一规则纠正一次；用户已经自己点过分段就不再动。
    @State private var selectedTab: Tab
    @State private var hasUserPickedTab: Bool = false
    @State private var addingSourceIDs: Set<String> = []
    @State private var failedSourceIDs: Set<String> = []
    @State private var isShowingEntryGuide: Bool = false

    init(viewModel: SourcesViewModel, openAddSource: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.openAddSource = openAddSource
        self._selectedTab = State(initialValue: Self.preferredTab(personalItemCount: viewModel.personalCatalogItemCount))
    }

    private static func preferredTab(personalItemCount: Int) -> Tab {
        return personalItemCount > 0 ? .personal : .recommended
    }

    /// 分段控件的绑定：用户点过就记下来，首次拉取回来后不再替用户改段。
    private var tabSelection: Binding<Tab> {
        return Binding<Tab>(
            get: { self.selectedTab },
            set: { newValue in
                self.hasUserPickedTab = true
                self.selectedTab = newValue
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch self.selectedTab {
                case .recommended:
                    self.recommendedContent
                case .personal:
                    self.personalContent
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // 中文注释：标题按设计稿自己画——「关闭」一行在上，下面是靠左的大标题，再下面是分段控件。
                // 系统导航栏标题在 sheet 里的位置与样式由系统决定，和稿子对不上，所以不用 navigationTitle。
                VStack(alignment: .leading, spacing: 16) {
                    Text(NSLocalizedString("catalog_title", comment: ""))
                        .font(.largeTitle.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                    CatalogSegmentedPicker(
                        selection: self.tabSelection,
                        segments: [
                            CatalogSegmentedPicker<Tab>.Segment(
                                value: Tab.recommended,
                                title: NSLocalizedString("catalog_tab_recommended", comment: ""),
                                systemImage: "sparkles"
                            ),
                            CatalogSegmentedPicker<Tab>.Segment(
                                value: Tab.personal,
                                title: NSLocalizedString("catalog_section_personal", comment: ""),
                                // 中文注释：目录页「我的生成」只在有条目时显示计数。
                                count: self.viewModel.personalCatalogItemCount > 0
                                    ? self.viewModel.personalCatalogItemCount
                                    : nil
                            )
                        ]
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .background(CatalogPalette.pageBackground)
            }
            .background(CatalogPalette.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            // `BC-PREFLIGHT-066`：每次打开都重新拉取，不再「已加载过即跳过」。
            .task {
                await self.viewModel.refreshCatalogSources()
                // 中文注释：首次拉取回来后再按「我的生成有条目就优先」纠正一次；用户已经点过分段就尊重用户。
                guard self.hasUserPickedTab == false else {
                    return
                }
                self.selectedTab = Self.preferredTab(personalItemCount: self.viewModel.personalCatalogItemCount)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                }
            }
            .sheet(isPresented: self.$isShowingEntryGuide) {
                NavigationStack {
                    // 中文注释：空状态里的教程入口不知道用户要生成哪种 kind，传 nil 走 kind 中性的举例。
                    EntryPageGuideView(
                        sourceKind: nil,
                        primaryTitleKey: "entry_guide_dismiss_button",
                        primaryAction: {
                            self.isShowingEntryGuide = false
                        },
                        cancelAction: nil
                    )
                }
            }
        }
    }

    private func refresh() async {
        await self.viewModel.refreshCatalogSources()
        self.failedSourceIDs.removeAll()
    }

    // MARK: - 推荐

    @ViewBuilder
    private var recommendedContent: some View {
        let sections: [CatalogKindSection] = CatalogKindSection.make(self.viewModel.defaultCatalogSources)
        ScrollView {
            if sections.isEmpty && self.viewModel.isLoadingCatalogSources {
                CatalogRecommendedSkeletonView()
            } else if sections.isEmpty {
                CatalogStateView(
                    systemImage: "books.vertical",
                    illustration: CatalogIllustration.named("CatalogEmptyRecommended"),
                    title: NSLocalizedString("catalog_empty", comment: ""),
                    message: NSLocalizedString("catalog_empty_message", comment: "")
                ) {
                    // 中文注释：刷新只靠下拉手势，不放重试按钮；可发现性做在这句示意上。
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.title3)
                        Text(NSLocalizedString("catalog_pull_to_reload", comment: ""))
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
                .containerRelativeFrame(.vertical)
            } else {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(sections) { section in
                        self.kindSection(section)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .refreshable {
            await self.refresh()
        }
    }

    private func kindSection(_ section: CatalogKindSection) -> some View {
        let style: CatalogKindStyle = CatalogKindStyle.of(section.kind)
        return VStack(alignment: .leading, spacing: 14) {
            CatalogKindBannerView(
                style: style,
                subtitle: NSLocalizedString("catalog_kind_swipe_hint", comment: "")
            )
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(section.sources, id: \.id) { catalogSource in
                        CatalogRecommendationCardView(
                            catalogSource: catalogSource,
                            accent: style.accent,
                            subtitle: CatalogDisplayText.recommendationSubtitle(
                                baseURL: catalogSource.baseURL,
                                entryURL: self.viewModel.catalogEntryURL(for: catalogSource)
                            ),
                            facts: self.viewModel.catalogRuleFacts[catalogSource.id],
                            appLanguage: CatalogLanguage.appLanguage,
                            action: self.actionState(for: catalogSource),
                            failureMessage: self.failureMessage(for: catalogSource),
                            addAction: {
                                self.add(catalogSource)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - 我的生成

    @ViewBuilder
    private var personalContent: some View {
        let timeline: CatalogPersonalTimeline = self.viewModel.personalCatalogTimeline
        if self.viewModel.isPersonalCatalogSignInRequired {
            ScrollView {
                CatalogStateView(
                    systemImage: "lock",
                    illustration: CatalogIllustration.named("CatalogPersonalSignIn"),
                    title: NSLocalizedString("catalog_personal_sign_in_title", comment: ""),
                    message: NSLocalizedString("catalog_personal_sign_in_hint", comment: "")
                ) {
                    Text(NSLocalizedString("catalog_personal_sign_in_where", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .containerRelativeFrame(.vertical)
            }
            .refreshable {
                await self.refresh()
            }
        } else if timeline.isEmpty && self.viewModel.isLoadingCatalogSources {
            ProgressView(NSLocalizedString("catalog_loading", comment: ""))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if timeline.isEmpty {
            ScrollView {
                self.personalEmptyState
                    .containerRelativeFrame(.vertical)
            }
            .refreshable {
                await self.refresh()
            }
        } else {
            List {
                CatalogRetentionNoticeView()
                    .catalogCardRow()
                ForEach(timeline.groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            self.personalRow(entry)
                                .catalogCardRow()
                        }
                    } header: {
                        Text(Self.dayTitle(group.day))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await self.refresh()
            }
        }
    }

    private var personalEmptyState: some View {
        CatalogStateView(
            systemImage: "wand.and.stars",
            illustration: CatalogIllustration.named("CatalogEmptyPersonal"),
            title: NSLocalizedString("catalog_personal_empty_title", comment: ""),
            message: NSLocalizedString("catalog_personal_empty_message", comment: "")
        ) {
            VStack(spacing: 14) {
                if let openAddSource: () -> Void = self.openAddSource {
                    Button {
                        openAddSource()
                        self.dismiss()
                    } label: {
                        Label(NSLocalizedString("catalog_personal_empty_add_source", comment: ""), systemImage: "plus")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 24)
                            .frame(minHeight: 46)
                            .foregroundStyle(CatalogPalette.onAction)
                            .background(CatalogPalette.addAction, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button(NSLocalizedString("entry_guide_reopen_link", comment: "")) {
                    self.isShowingEntryGuide = true
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func personalRow(_ entry: CatalogPersonalTimeline.Entry) -> some View {
        switch entry {
        case .rule(let catalogSource):
            CatalogPersonalRuleCardView(
                catalogSource: catalogSource,
                entryURL: self.viewModel.catalogEntryURL(for: catalogSource) ?? catalogSource.baseURL,
                remainingText: self.remainingText(for: catalogSource),
                remainingFraction: self.viewModel.personalRuleRemainingFraction(for: catalogSource),
                action: self.actionState(for: catalogSource),
                failureMessage: self.failureMessage(for: catalogSource),
                addAction: {
                    self.add(catalogSource)
                }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task {
                        await self.viewModel.deletePersonalRule(catalogSourceID: catalogSource.id)
                    }
                } label: {
                    Label(NSLocalizedString("catalog_personal_delete", comment: ""), systemImage: "trash")
                }
            }
        case .failure(let outcome):
            FailedGenerationOutcomeCardView(outcome: outcome)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            await self.viewModel.deleteFailedGenerationOutcome(jobID: outcome.jobID)
                        }
                    } label: {
                        Label(NSLocalizedString("catalog_personal_delete", comment: ""), systemImage: "trash")
                    }
                }
        }
    }

    static func dayTitle(_ day: CatalogPersonalTimeline.Day) -> String {
        return CatalogDayTitle.text(for: day)
    }

    private func remainingText(for catalogSource: CatalogSource) -> String? {
        guard let remaining: (days: Int, hours: Int) =
            self.viewModel.personalRuleRemainingComponents(for: catalogSource) else {
            return nil
        }
        if remaining.days == 0 && remaining.hours == 0 {
            return NSLocalizedString("catalog_personal_remaining_none", comment: "")
        }
        if remaining.days == 0 {
            return String(format: NSLocalizedString("catalog_personal_remaining_hours", comment: ""), remaining.hours)
        }
        return String(
            format: NSLocalizedString("catalog_personal_remaining_days_hours", comment: ""),
            remaining.days,
            remaining.hours
        )
    }

    // MARK: - 添加

    private func actionState(for catalogSource: CatalogSource) -> CatalogAddActionState {
        if self.addingSourceIDs.contains(catalogSource.id) {
            return .adding
        }
        if self.viewModel.isCatalogSourceAdded(catalogSource) {
            return .added
        }
        return .add
    }

    private func failureMessage(for catalogSource: CatalogSource) -> String? {
        guard self.failedSourceIDs.contains(catalogSource.id) else {
            return nil
        }
        return self.viewModel.catalogSourceAddFailureMessages[catalogSource.id]
            ?? NSLocalizedString("catalog_add_failed", comment: "")
    }

    private func add(_ catalogSource: CatalogSource) {
        // 中文注释：已添加的来源没有动作——规则变了由 `applyCatalogRuleUpdates` 在读取目录时自动覆盖。
        if self.addingSourceIDs.contains(catalogSource.id)
            || self.viewModel.isCatalogSourceAdded(catalogSource) {
            return
        }

        self.addingSourceIDs.insert(catalogSource.id)
        self.failedSourceIDs.remove(catalogSource.id)

        Task {
            let didAdd: Bool = await self.viewModel.addCatalogSource(
                catalogSource,
                shouldPresentError: false
            )
            await MainActor.run {
                self.addingSourceIDs.remove(catalogSource.id)
                if didAdd {
                    self.dismiss()
                } else {
                    self.failedSourceIDs.insert(catalogSource.id)
                }
            }
        }
    }
}

// MARK: - 分段控件

/// 「推荐 / 我的生成」两段。「我的生成」段带数量角标，为 0 时不显示。
// MARK: - 推荐：横幅与卡片

enum CatalogAddActionState: Hashable {
    case add
    case adding
    case added
}

private struct CatalogRecommendationCardView: View {
    let catalogSource: CatalogSource
    let accent: Color
    let subtitle: String
    /// 规则里给用户看的信息；解析不了时为 nil，卡片只显示名称与地址。
    let facts: CatalogRuleFacts?
    let appLanguage: String
    let action: CatalogAddActionState
    let failureMessage: String?
    let addAction: () -> Void

    private var languageTag: String? {
        guard let language: String = self.facts?.language else {
            return nil
        }
        return CatalogLanguage.tag(for: language, appLanguage: self.appLanguage)
    }

    var body: some View {
        // 中文注释：徽标单独一行、标签靠右；站点名与主机名各占整行——180pt 宽的卡片里，
        // 名字若与徽标并排只剩约 90pt，「站名 · 分类」这类名字一截就看不全（09-30 真机截图）。
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                CatalogMonogramView(name: self.catalogSource.name, accent: self.accent, size: 36)
                Spacer(minLength: 0)
                self.tagGroup
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(self.catalogSource.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(self.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let failureMessage: String = self.failureMessage {
                Text(failureMessage)
                    .font(.caption)
                    .foregroundStyle(CatalogPalette.warning)
                    .lineLimit(2)
            }
            if let facts: CatalogRuleFacts = self.facts, let summary: String = facts.categorySummary() {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        facts.categoryTitles.count >= 2
                            ? String(
                                format: NSLocalizedString("catalog_card_category_count", comment: ""),
                                facts.categoryTitles.count
                            )
                            : NSLocalizedString("catalog_card_category_single", comment: "")
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            self.actionView
        }
        .padding(14)
        .frame(width: 180, alignment: .topLeading)
        .frame(minHeight: 244, alignment: .topLeading)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 「可搜索」与语言标签，放在徽标右侧；一行放不下时靠右竖排。
    @ViewBuilder
    private var tagGroup: some View {
        let searchable: Bool = self.facts?.supportsSearch ?? false
        let language: String? = self.languageTag
        if searchable || language != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    self.tags(searchable: searchable, language: language)
                }
                VStack(alignment: .trailing, spacing: 4) {
                    self.tags(searchable: searchable, language: language)
                }
            }
        }
    }

    @ViewBuilder
    private func tags(searchable: Bool, language: String?) -> some View {
        if searchable {
            CatalogTagView(
                title: NSLocalizedString("catalog_card_searchable", comment: ""),
                systemImage: "magnifyingglass"
            )
        }
        if let language: String = language {
            CatalogTagView(title: language, systemImage: nil)
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch self.action {
        case .adding:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(CatalogPalette.fillBackground, in: Capsule())
        case .added:
            Label("Added", systemImage: "checkmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(CatalogPalette.fillBackground, in: Capsule())
        case .add:
            Button(action: self.addAction) {
                Label("Add", systemImage: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CatalogPalette.onAction)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(CatalogPalette.addAction, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(format: NSLocalizedString("catalog_add_accessibility", comment: ""), self.catalogSource.name)
            )
        }
    }
}

private struct CatalogTagView: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage: String = self.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(self.title)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .frame(minHeight: 20)
        .background(CatalogPalette.fillBackground, in: Capsule())
    }
}

/// 首字徽标：目录卡片与来源页的来源行、正在使用卡片共用。
struct CatalogMonogramView: View {
    let name: String
    let accent: Color
    let size: CGFloat

    var body: some View {
        Text(CatalogDisplayText.monogram(for: self.name))
            .font(.system(size: self.size * 0.45, weight: .bold))
            .foregroundStyle(self.accent)
            .frame(width: self.size, height: self.size)
            .background(self.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: self.size * 0.29, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 推荐的加载骨架：与正式页同形（横幅 + 三张卡片 × 两个分区），加载完成后页面不跳动。
private struct CatalogRecommendedSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ForEach(0 ..< 2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(CatalogPalette.cardBackground)
                        .frame(height: 112)
                        .padding(.horizontal, 20)
                    HStack(spacing: 12) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(CatalogPalette.cardBackground)
                                .frame(width: 180, height: 244)
                        }
                    }
                    .padding(.horizontal, 20)
                    // 中文注释：三张 180pt 卡片加边距共 604pt，比手机屏宽。只给 maxWidth 时 frame 会取子视图的宽度，
                    // 整页内容被撑到 604pt 再居中，标题与分段控件一起向左溢出；同时给 minWidth: 0，frame 才采用父视图给的宽度，
                    // 多出的卡片由 clipped() 裁掉。
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
            }
            HStack(spacing: 8) {
                ProgressView()
                Text(NSLocalizedString("catalog_loading", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("catalog_loading", comment: ""))
    }
}

// MARK: - 我的生成：卡片

private extension View {
    /// 时间线里的卡片行：去掉分隔线与行底色，左右留 20pt，卡片之间留 10pt。
    func catalogCardRow() -> some View {
        return self
            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct CatalogRetentionNoticeView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
            Text(NSLocalizedString("catalog_personal_retention_hint", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CatalogPersonalRuleCardView: View {
    let catalogSource: CatalogSource
    let entryURL: String
    let remainingText: String?
    let remainingFraction: Double?
    let action: CatalogAddActionState
    let failureMessage: String?
    let addAction: () -> Void

    /// 剩余不足 1 天时进度条与文案改用警示色。
    private var isExpiringSoon: Bool {
        guard let remainingFraction: Double = self.remainingFraction else {
            return false
        }
        return remainingFraction < 1.0 / 7.0
    }

    var body: some View {
        let style: CatalogKindStyle = CatalogKindStyle.of(self.catalogSource.kind)
        let address: (host: String, rest: String) = CatalogDisplayText.addressParts(of: self.entryURL)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CatalogMonogramView(name: self.catalogSource.name, accent: style.accent, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.catalogSource.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(Self.addressText(address))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let failureMessage: String = self.failureMessage {
                        Text(failureMessage)
                            .font(.caption)
                            .foregroundStyle(CatalogPalette.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                self.trailingControl
            }
            if let remainingText: String = self.remainingText {
                HStack(spacing: 10) {
                    ProgressView(value: self.remainingFraction ?? 0)
                        .progressViewStyle(.linear)
                        .tint(self.isExpiringSoon ? CatalogPalette.warning : Color.primary.opacity(0.8))
                    Text(remainingText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(self.isExpiringSoon ? CatalogPalette.warning : .secondary)
                }
                .padding(.leading, 54)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(remainingText)
            }
        }
        .padding(14)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 主机名用次级色，路径用更浅的三级色，一行截断。
    private static func addressText(_ address: (host: String, rest: String)) -> AttributedString {
        let host: AttributedString = AttributedString(address.host)
        var rest: AttributedString = AttributedString(address.rest)
        rest.foregroundColor = CatalogPalette.tertiaryText
        return host + rest
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch self.action {
        case .adding:
            ProgressView()
                .frame(width: 36, height: 36)
        case .added:
            Label("Added", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(CatalogPalette.fillBackground, in: Capsule())
        case .add:
            Button(action: self.addAction) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CatalogPalette.onAction)
                    .frame(width: 36, height: 36)
                    .background(CatalogPalette.addAction, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-4)
            .accessibilityLabel(
                String(format: NSLocalizedString("catalog_add_accessibility", comment: ""), self.catalogSource.name)
            )
        }
    }
}

/// 失败的生成任务：「生成失败」标签 + 入口 URL，下面是面向用户的成因（`reason`），有细分时再补一句（`reasonDetail`）。
private struct FailedGenerationOutcomeCardView: View {
    let outcome: VideoGenerationOutcome

    @State private var isShowingGuide: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CatalogPalette.warning)
                .frame(width: 42, height: 42)
                .background(CatalogPalette.warningFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(NSLocalizedString("catalog_generation_failed_badge", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CatalogPalette.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(CatalogPalette.warningFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(self.outcome.entryURL ?? self.outcome.jobID.uuidString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(VideoGenerationOutcomeText.reasonText(for: self.outcome))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail: String = VideoGenerationOutcomeText.reasonDetailText(for: self.outcome) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 中文注释：入口页资格拒因（`BC-PAGE-060` 的四种）说的就是「这一页不合格」，
                // 下一步是换一个合格的页面——把教程接在这里，用户不必自己去添加来源里翻。
                if VideoGenerationOutcomeText.isEntryPageRejection(self.outcome) {
                    Button {
                        self.isShowingGuide = true
                    } label: {
                        HStack(spacing: 2) {
                            Text(NSLocalizedString("entry_guide_open_from_failure", comment: ""))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CatalogPalette.warning.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: self.$isShowingGuide) {
            NavigationStack {
                // 中文注释：`/outcomes` 不带 sourceKind，这里只能传 nil，举例走 kind 中性那句。
                EntryPageGuideView(
                    sourceKind: nil,
                    primaryTitleKey: "entry_guide_dismiss_button",
                    primaryAction: {
                        self.isShowingGuide = false
                    },
                    cancelAction: nil
                )
            }
        }
    }
}

// MARK: - 空状态

/// 目录页的空 / 未登录状态：插画（缺失时退回系统符号）+ 标题 + 说明 + 各自的下一步。
private struct CatalogStateView<Accessory: View>: View {
    let systemImage: String
    let illustration: String?
    let title: String
    let message: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 12) {
            EmptyStateIconView(systemImage: self.systemImage, illustration: self.illustration)
            Text(self.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(self.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            self.accessory()
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 极梦插画的资产名 → 资源目录里有才返回，没有时空状态退回系统符号。
enum CatalogIllustration {
    static func named(_ name: String) -> String? {
        return UIImage(named: name) == nil ? nil : name
    }
}

/// 成因 → 本地化文案。键与推送的 `push_generation_failed_*` 同一套 reason 后缀，
/// 两条通道对同一次失败说同一句话；未知值降级到通用文案。
enum VideoGenerationOutcomeText {
    static let knownReasons: Set<String> = [
        "siteRejectedFetcher", "siteNotSupported", "siteUnreachable",
        "inputInvalid", "evidenceInsufficient", "temporaryFailure",
        // `BC-ACQ-072`：困难模式下云端对该站按最高档计费、产品不开这一档——下一步只能换站。
        "hardModeSiteTooStrong"
    ]
    // `BC-PAGE-060` 的四种入口页拒因（服务端 `BC-PREFLIGHT-056` 2026-09-20 修订）并进这张表。
    // 不在表里的细分一律不显示，只留 `reason` 的通用文案——服务端先于 App 上线新值是常态。
    static let knownReasonDetails: Set<String> = Set<String>([
        "noPlaybackCarrier", "episodeLayoutUnsupported",
        // `BC-IMPL-139`：终端页已取到却没有可识别的内容载体（按 kind 中立措辞）。
        "terminalPagesWithoutCarrier",
        // `BC-PAGE-061`：内容要额外请求数据接口或解密才能取到——换网站，不是换入口页。
        "contentNotServerRendered",
        // `BC-BOOK-058`：作品页只列最新几章、完整目录要另经接口取得——换一个网站。
        "chapterListLatestOnly",
        // `BC-IMPL-127` 第六种情况 / `BC-IMPL-142`：列表没问题，点进去的作品页认不出结构——换一个网站。
        "detailPagesUnrecognized"
    ]).union(Self.entryPageRejectionDetails)

    static func reasonText(for outcome: VideoGenerationOutcome) -> String {
        guard let reason: String = outcome.reason, Self.knownReasons.contains(reason) else {
            return NSLocalizedString("video_generation_outcome_failed_unknown", comment: "")
        }
        return NSLocalizedString("video_generation_outcome_failed_\(reason)", comment: "")
    }

    /// `BC-PAGE-060` 的四种入口页拒因——它们都指向同一件事：换一个合格的入口页。
    /// `BC-PAGE-062` 追加 `entryPageIsSiteRoot`：首页入口不再支持，下一步同样是换入口页。
    /// `BC-LIST-112` 追加 `entryPagePaginationUnverified`：翻页地址推得出但第 2 页核验不过，下一步仍是换入口页。
    static let entryPageRejectionDetails: Set<String> = [
        "entryPageWithoutPagination", "entryPageMultipleListFamilies",
        "entryPageNoListFamily", "entryPageShapeAmbiguous",
        "entryPageIsSiteRoot", "entryPagePaginationUnverified"
    ]

    static func isEntryPageRejection(_ outcome: VideoGenerationOutcome) -> Bool {
        guard let detail: String = outcome.reasonDetail else {
            return false
        }
        return Self.entryPageRejectionDetails.contains(detail)
    }

    static func reasonDetailText(for outcome: VideoGenerationOutcome) -> String? {
        guard let detail: String = outcome.reasonDetail, Self.knownReasonDetails.contains(detail) else {
            return nil
        }
        return NSLocalizedString("video_generation_outcome_detail_\(detail)", comment: "")
    }
}
