import BrowseCraftDomain
import SwiftUI

// 中文注释：SourcesView.swift 属于界面功能层，承载来源页（`docs/design/Sources-Page-Redesign-Design.md` 方案 A）。

/// 来源页：顶部「目录 | 添加」与来源位置条；正在使用的来源是一张类型色深色瓷砖，其余分「其他来源」与「已暂停」两组。
/// 点任意来源 = 用它打开库：当前来源直接切到库，其他来源先切换、成功后再切到库，失败留在本页照现状报错。
@MainActor
struct SourcesView: View {
    @Bindable var viewModel: SourcesViewModel
    @Bindable var cloudSyncViewModel: CloudSyncSettingsViewModel
    /// 宿主切到库标签。
    let openLibrary: () -> Void
    /// 宿主打开既有的高级版购买入口（来源位置不够时）。
    let openPremium: () -> Void

    @State private var isShowingAddSourceView: Bool = false
    @State private var isShowingCatalogSourceListView: Bool = false
    @State private var opensAddSourceAfterCatalog: Bool = false
    @State private var opensPremiumAfterSlotActivation: Bool = false
    @State private var debugSourceID: String?

    var body: some View {
        NavigationStack {
            self.content
                .background(CatalogPalette.pageBackground)
                // 中文注释：标题与「目录 | 添加」按设计稿自己画在内容里（大标题靠左、胶囊靠右同一行），
                // 系统导航栏只在推入来源详情时出现；标题仍要设，作为详情页返回按钮的文字。
                .toolbar(.hidden, for: .navigationBar)
                .navigationTitle("Sources")
                .navigationDestination(item: self.$debugSourceID) { sourceID in
                    SourceDebugView(viewModel: self.viewModel, sourceID: sourceID)
                }
                .onAppear {
                    CrashDiagnostics.shared.setScreen(.sourceList)
                    AppAnalytics.shared.logScreenView(.sourceList)
                    Task {
                        await self.viewModel.load()
                    }
                }
                .onChange(of: self.cloudSyncViewModel.contentRevision) { _, _ in
                    Task {
                        await self.viewModel.load()
                    }
                }
                .sheet(isPresented: self.$isShowingAddSourceView) {
                    AddSourceView(viewModel: self.viewModel)
                }
                .sheet(
                    isPresented: self.$isShowingCatalogSourceListView,
                    onDismiss: {
                        // 中文注释：目录页「我的生成」空状态点了「去添加来源」——等目录页收起后再弹添加来源，
                        // 两个 sheet 不能同时呈现。
                        if self.opensAddSourceAfterCatalog {
                            self.opensAddSourceAfterCatalog = false
                            self.isShowingAddSourceView = true
                        }
                    }
                ) {
                    CatalogSourceListView(
                        viewModel: self.viewModel,
                        openAddSource: {
                            self.opensAddSourceAfterCatalog = true
                        }
                    )
                }
                .sheet(
                    item: self.slotActivationBinding,
                    onDismiss: {
                        // 中文注释：启用窗口里点了「获取更多位置」——窗口收起后再切到购买入口。
                        if self.opensPremiumAfterSlotActivation {
                            self.opensPremiumAfterSlotActivation = false
                            self.openPremium()
                        }
                    }
                ) { source in
                    SourceSlotActivationView(
                        lockedSource: source,
                        activeSources: self.viewModel.activeCustomSources,
                        selectedSourceID: self.viewModel.selectedSourceID,
                        freeSlotCount: max(0, self.viewModel.sourceSlotLimit - self.viewModel.occupiedSourceSlotCount),
                        canActivateWithoutReplacement:
                            self.viewModel.canActivateRequestedSourceWithoutReplacement,
                        activationAction: { replacingSourceID in
                            return await self.viewModel.activateRequestedSource(
                                replacingSourceID: replacingSourceID
                            )
                        },
                        getMoreSlotsAction: {
                            self.opensPremiumAfterSlotActivation = true
                        }
                    )
                }
                .alert(isPresented: self.errorAlertBinding) {
                    self.errorAlert()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if self.shouldShowInitialRestore {
            self.restoreContent
        } else if self.viewModel.sources.isEmpty {
            self.emptyContent
        } else {
            self.sourceList
        }
    }

    // MARK: - 来源列表

    private var sourceList: some View {
        let currentSource: Source? = self.currentSource
        let otherSources: [Source] = self.otherSources
        let pausedSources: [Source] = self.pausedSources
        let isSwitching: Bool = self.viewModel.isRefreshing

        // 中文注释：用 List 而不是 ScrollView，是为了保留左滑删除（2.5）。行底色、分隔线都关掉，卡片在行内容里自己画。
        return List {
            self.header
                .sourcesPageRow(top: 8)

            SourceSlotBarView(
                used: self.viewModel.occupiedSourceSlotCount,
                limit: self.viewModel.sourceSlotLimit,
                moreAction: self.openPremium
            )
            .sourcesPageRow(top: 16)

            if let currentSource: Source = currentSource {
                SourceInUseCardView(source: currentSource, action: self.openLibrary)
                    .disabled(isSwitching)
                    .opacity(isSwitching ? 0.45 : 1)
                    .contextMenu {
                        self.menu(for: currentSource)
                    }
                    .swipeToDelete(currentSource, disabled: isSwitching) { source in
                        self.delete(source)
                    }
                    .sourcesPageRow(top: 18)
            }

            if otherSources.isEmpty == false {
                self.sectionHeader(
                    title: NSLocalizedString("sources_section_others", comment: ""),
                    trailing: NSLocalizedString(
                        isSwitching ? "sources_section_others_switching" : "sources_section_others_hint",
                        comment: ""
                    ),
                    color: .secondary
                )
                .sourcesPageRow(top: 22, bottom: 8, horizontal: 24)

                ForEach(Array(otherSources.enumerated()), id: \.element.id) { index, source in
                    let isSwitchingRow: Bool = source.id == self.viewModel.refreshingSourceID
                    SourceRowView(
                        source: source,
                        role: .other(isSwitching: isSwitchingRow),
                        isFirst: index == 0,
                        isLast: index == otherSources.count - 1,
                        action: {
                            self.switchAndOpenLibrary(source)
                        }
                    )
                    .disabled(isSwitching)
                    .opacity(isSwitching && isSwitchingRow == false ? 0.45 : 1)
                    .contextMenu {
                        self.menu(for: source)
                    }
                    .swipeToDelete(source, disabled: isSwitching) { source in
                        self.delete(source)
                    }
                    .sourcesPageRow()
                }
            }

            if self.showsSlotsFullHint(otherSources: otherSources, pausedSources: pausedSources) {
                SourceSlotsFullHintView(getMoreSlotsAction: self.openPremium)
                    .sourcesPageRow(top: 16)
            }

            if pausedSources.isEmpty == false {
                self.sectionHeader(
                    title: NSLocalizedString("sources_section_paused", comment: ""),
                    trailing: nil,
                    color: CatalogPalette.warning
                )
                .sourcesPageRow(top: 22, bottom: 8, horizontal: 24)

                ForEach(Array(pausedSources.enumerated()), id: \.element.id) { index, source in
                    SourceRowView(
                        source: source,
                        role: .paused(
                            canActivateWithoutReplacement:
                                self.viewModel.canActivateRequestedSourceWithoutReplacement
                        ),
                        isFirst: index == 0,
                        isLast: index == pausedSources.count - 1,
                        action: {
                            self.viewModel.requestSlotActivation(for: source)
                        }
                    )
                    .disabled(isSwitching)
                    .opacity(isSwitching ? 0.45 : 1)
                    .contextMenu {
                        self.menu(for: source)
                    }
                    .swipeToDelete(source, disabled: isSwitching) { source in
                        self.delete(source)
                    }
                    .sourcesPageRow()
                }
            }

            Text(NSLocalizedString("sources_footer_hint", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .sourcesPageRow(top: 14, bottom: 24, horizontal: 24)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text("Sources")
                .font(.largeTitle.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            SourcesActionCapsule(
                catalogAction: {
                    self.isShowingCatalogSourceListView = true
                },
                addAction: {
                    self.isShowingAddSourceView = true
                }
            )
        }
    }

    private func sectionHeader(title: String, trailing: String?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Spacer(minLength: 8)
            if let trailing: String = trailing {
                Text(trailing)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(.footnote)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func menu(for source: Source) -> some View {
        let isSwitching: Bool = self.viewModel.isRefreshing
        if source.accessState == .lockedBySlotLimit {
            Button {
                self.viewModel.requestSlotActivation(for: source)
            } label: {
                Label(
                    NSLocalizedString(
                        self.viewModel.canActivateRequestedSourceWithoutReplacement
                            ? "sources_paused_activate"
                            : "sources_paused_replace",
                        comment: ""
                    ),
                    systemImage: "lock.open"
                )
            }
            .disabled(isSwitching)
        } else if source.id == self.viewModel.selectedSourceID {
            Button {
                self.openLibrary()
            } label: {
                Label(NSLocalizedString("sources_menu_open_library", comment: ""), systemImage: "square.grid.2x2")
            }
        } else {
            Button {
                self.switchAndOpenLibrary(source)
            } label: {
                Label(NSLocalizedString("sources_menu_switch_and_open", comment: ""), systemImage: "square.grid.2x2")
            }
            .disabled(isSwitching)
        }

        Button {
            self.debugSourceID = source.id
        } label: {
            Label(NSLocalizedString("sources_menu_details", comment: ""), systemImage: "info.circle")
        }

        Divider()

        Button(role: .destructive) {
            self.delete(source)
        } label: {
            Label(NSLocalizedString("sources_menu_delete", comment: ""), systemImage: "trash")
        }
        .disabled(isSwitching)
    }

    /// 删除来源不弹确认（2026-10-03 用户裁定），左滑与长按「删除来源」都直接删；连带清理历史与库状态的逻辑不变。
    private func delete(_ source: Source) {
        Task {
            await self.viewModel.deleteSource(id: source.id)
        }
    }

    /// 点其他来源：先切换（加载第一页、发布库快照），成功后再切到库；失败时 ViewModel 已给出错误，留在本页。
    private func switchAndOpenLibrary(_ source: Source) {
        Task {
            if await self.viewModel.selectSourceAfterRefresh(source) {
                self.openLibrary()
            }
        }
    }

    /// 位置已满、又只有正在使用的这一个来源：提示想再加网站要先删或买位置（2.7）。
    private func showsSlotsFullHint(otherSources: [Source], pausedSources: [Source]) -> Bool {
        return self.currentSource != nil
            && otherSources.isEmpty
            && pausedSources.isEmpty
            && self.viewModel.occupiedSourceSlotCount >= self.viewModel.sourceSlotLimit
    }

    private var currentSource: Source? {
        guard let source: Source = self.viewModel.selectedSource, source.accessState == .active else {
            return nil
        }
        return source
    }

    private var otherSources: [Source] {
        let currentSourceID: String? = self.currentSource?.id
        return self.viewModel.sources.filter { source in
            return source.accessState == .active && source.id != currentSourceID
        }
    }

    private var pausedSources: [Source] {
        return self.viewModel.sources.filter { source in
            return source.accessState == .lockedBySlotLimit
        }
    }

    // MARK: - 没有来源

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("Sources")
                        .font(.largeTitle.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: self.slotCountText)
                            .font(.headline.weight(.heavy))
                            .monospacedDigit()
                        Text(NSLocalizedString("sources_slots_short", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(NSLocalizedString("sources_slots_used", comment: ""))
                    .accessibilityValue(self.slotCountText)
                }
                .padding(.top, 8)

                VStack(spacing: 10) {
                    EmptyStateIconView(systemImage: "tray", illustration: "EmptyStateSources")
                    Text(NSLocalizedString("sources_empty_title", comment: ""))
                        .font(.title2.weight(.heavy))
                        .multilineTextAlignment(.center)
                    Text(NSLocalizedString("sources_empty_message", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 26)

                VStack(spacing: 12) {
                    SourcesEntryCardView(
                        title: NSLocalizedString("sources_empty_catalog_title", comment: ""),
                        message: NSLocalizedString("sources_empty_catalog_message", comment: ""),
                        systemImage: "sparkles",
                        iconForeground: .white,
                        iconBackground: CatalogPalette.addAction,
                        action: {
                            self.isShowingCatalogSourceListView = true
                        }
                    )
                    SourcesEntryCardView(
                        title: NSLocalizedString("sources_empty_generate_title", comment: ""),
                        message: NSLocalizedString("sources_empty_generate_message", comment: ""),
                        systemImage: "link",
                        iconForeground: Color(uiColor: .systemBackground),
                        iconBackground: .primary,
                        action: {
                            self.isShowingAddSourceView = true
                        }
                    )
                }
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
    }

    private var slotCountText: String {
        return "\(self.viewModel.occupiedSourceSlotCount) / \(self.viewModel.sourceSlotLimit)"
    }

    // MARK: - iCloud 首次恢复

    /// 位置条显示「— / —」，中部为恢复卡片与两条骨架；恢复失败时下拉重试（2.7，不放重试按钮）。
    private var restoreContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                self.header
                    .padding(.top, 8)
                SourceSlotBarView(used: nil, limit: nil, moreAction: nil)
                CloudSyncInitialRestoreView(state: self.cloudSyncViewModel.initialRestoreState)
                VStack(spacing: 10) {
                    ForEach([0.6, 0.4], id: \.self) { opacity in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(CatalogPalette.cardBackground)
                            .frame(height: 64)
                            .opacity(opacity)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable {
            await self.cloudSyncViewModel.retryInitialRestoreIfFailed()
        }
    }

    private var shouldShowInitialRestore: Bool {
        let hasCustomSources: Bool = self.viewModel.sources.contains { source in
            return source.id.hasPrefix("built-in.") == false
        }
        return hasCustomSources == false &&
            self.cloudSyncViewModel.initialRestoreState.shouldReplaceEmptyState
    }

    // MARK: - 绑定与提示

    private var slotActivationBinding: Binding<Source?> {
        return Binding(
            get: {
                return self.viewModel.requestedSlotActivationSource
            },
            set: { source in
                if source == nil {
                    self.viewModel.dismissRequestedSlotActivation()
                }
            }
        )
    }

    private func errorAlert() -> Alert {
        if self.viewModel.canRetryFailedRefresh {
            return Alert(
                title: Text("Sources"),
                message: Text(self.viewModel.errorMessage ?? ""),
                primaryButton: .default(
                    Text("Retry"),
                    action: {
                        Task {
                            // 中文注释：重试的是一次「切换并打开库」，成功后照样切到库。
                            if await self.viewModel.retryFailedRefresh() {
                                self.openLibrary()
                            }
                        }
                    }
                ),
                secondaryButton: .cancel(
                    Text("Cancel"),
                    action: {
                        self.viewModel.clearError()
                    }
                )
            )
        }

        return Alert(
            title: Text("Sources"),
            message: Text(self.viewModel.errorMessage ?? ""),
            dismissButton: .default(
                Text("OK"),
                action: {
                    self.viewModel.clearError()
                }
            )
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.viewModel.errorMessage != nil
            },
            set: { newValue in
                if newValue == false {
                    self.viewModel.clearError()
                }
            }
        )
    }
}

private extension View {
    /// 来源页列表里的一行：去掉系统行底色与分隔线，左右留白、上下间距由调用处给。
    func sourcesPageRow(top: CGFloat = 0, bottom: CGFloat = 0, horizontal: CGFloat = 20) -> some View {
        return self
            .listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// 左滑删除：直接删，不弹确认。不用 destructive 角色，行的移除由数据变化驱动。
    func swipeToDelete(_ source: Source, disabled: Bool, action: @escaping (Source) -> Void) -> some View {
        return self.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                action(source)
            } label: {
                Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
            }
            .tint(CatalogPalette.destructive)
            .disabled(disabled)
        }
    }
}

/// 右上的「✦ 目录 | ＋ 添加」：同一底色、同一字号字重，中间细分隔线，两段等权（2.1）。
private struct SourcesActionCapsule: View {
    let catalogAction: () -> Void
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            self.segment(
                title: NSLocalizedString("sources_action_catalog", comment: ""),
                // 中文注释：与规则目录页「推荐」标签同一个图标。
                systemImage: "sparkles",
                action: self.catalogAction
            )
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 1, height: 20)
                .accessibilityHidden(true)
            self.segment(
                title: NSLocalizedString("sources_action_add", comment: ""),
                systemImage: "plus",
                action: self.addAction
            )
        }
        .background(CatalogPalette.cardBackground, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    private func segment(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // 中文注释：单行且不被压缩——标题与胶囊同一行，宽度不够时让标题缩字号，而不是把「目录」挤成竖排。
            // 不用 `Label`：它在列表行里加 `fixedSize` 后会退化成只显示图标。
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 位置已满且只有一个来源时的提示卡：「想再加一个网站？」。
private struct SourceSlotsFullHintView: View {
    let getMoreSlotsAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "plus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(CatalogPalette.fillBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("sources_full_hint_title", comment: ""))
                    .font(.subheadline.weight(.semibold))
                Text(NSLocalizedString("sources_full_hint_message", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(NSLocalizedString("sources_get_more_slots", comment: "")) {
                    self.getMoreSlotsAction()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CatalogPalette.addAction)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 空状态里的入口卡片：彩色方图标 + 标题 + 一句说明 + ›。来源页与收藏页的空状态共用。
struct SourcesEntryCardView: View {
    let title: String
    let message: String
    let systemImage: String
    let iconForeground: Color
    let iconBackground: Color
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 14) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(self.iconForeground)
                    .frame(width: 48, height: 48)
                    .background(self.iconBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(self.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 启用来源窗口（2.6）：逻辑不变（`activateRequestedSource`），外观为方案 A。
@MainActor
private struct SourceSlotActivationView: View {
    @Environment(\.dismiss) private var dismiss
    let lockedSource: Source
    let activeSources: [Source]
    let selectedSourceID: String?
    let freeSlotCount: Int
    let canActivateWithoutReplacement: Bool
    let activationAction: (String?) async -> Bool
    /// 「获取更多位置」：宿主在窗口收起后打开购买入口。
    let getMoreSlotsAction: () -> Void

    @State private var isActivating: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.lockedSourceTile
                    Text(NSLocalizedString("sources_activation_saved", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 12)

                    if self.canActivateWithoutReplacement {
                        self.activateContent
                    } else {
                        self.replaceContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(CatalogPalette.pageBackground)
            .navigationTitle("Activate Source")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(self.isActivating)
            .overlay {
                if self.isActivating {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                }
            }
        }
    }

    /// 顶部为被暂停来源的类型色深色卡片，徽章「已暂停 · 类型」。
    private var lockedSourceTile: some View {
        let style: CatalogKindStyle = CatalogKindStyle.of(self.lockedSource)
        return VStack(alignment: .leading, spacing: 14) {
            SourceTileBadgeView(
                title: String(format: NSLocalizedString("sources_activation_badge", comment: ""), style.title),
                systemImage: "lock",
                foreground: CatalogKindStyle.bannerTitle,
                background: Color.white.opacity(0.14)
            )
            SourceTileIdentityView(
                name: self.lockedSource.name,
                subtitle: SourceDisplayText.origin(of: self.lockedSource),
                style: style
            )
        }
        .sourceTile(style: style)
        .accessibilityElement(children: .combine)
    }

    /// 有空余位置：一个「启用这个来源」按钮与剩余位置数。
    private var activateContent: some View {
        VStack(spacing: 10) {
            Button {
                self.activate(replacingSourceID: nil)
            } label: {
                Text(NSLocalizedString("sources_activation_activate", comment: ""))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(CatalogPalette.addAction, in: Capsule())
            }
            .buttonStyle(.plain)
            Text(String(format: NSLocalizedString("sources_activation_free_slots", comment: ""), self.freeSlotCount))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    /// 位置已满：列出正在使用的来源，每行末尾「换下」；底部说明被换下的来源会移到「已暂停」。
    private var replaceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("sources_activation_full_title", comment: ""))
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(self.activeSources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 68)
                    }
                    self.replaceRow(source)
                }
            }
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(NSLocalizedString("sources_activation_full_footer", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 10)
            Button(NSLocalizedString("sources_get_more_slots", comment: "")) {
                self.getMoreSlotsAction()
                self.dismiss()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CatalogPalette.addAction)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
    }

    private func replaceRow(_ source: Source) -> some View {
        let style: CatalogKindStyle = CatalogKindStyle.of(source)
        let status: String = source.id == self.selectedSourceID
            ? NSLocalizedString("sources_in_use_badge", comment: "")
            : SourceDisplayText.origin(of: source)
        return Button {
            self.activate(replacingSourceID: source.id)
        } label: {
            HStack(spacing: 12) {
                CatalogMonogramView(name: source.name, accent: style.accent, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(verbatim: "\(style.title) · \(status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(NSLocalizedString("sources_activation_swap_out", comment: ""))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CatalogPalette.warning)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .overlay(Capsule().strokeBorder(CatalogPalette.warning, lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activate(replacingSourceID: String?) {
        guard self.isActivating == false else {
            return
        }
        self.isActivating = true

        Task {
            _ = await self.activationAction(replacingSourceID)
            self.isActivating = false
            self.dismiss()
        }
    }
}
