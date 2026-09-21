import SwiftUI
import BrowseCraftDomain

struct CatalogSourceListView: View {
    @Bindable var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var addingSourceIDs: Set<String> = []
    @State private var failedSourceIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if self.viewModel.isLoadingCatalogSources && self.viewModel.catalogSources.isEmpty {
                    ProgressView(NSLocalizedString("catalog_loading", comment: ""))
                } else if self.viewModel.catalogSources.isEmpty {
                    Text(NSLocalizedString("catalog_empty", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    self.personalSection
                    Section(header: Text(NSLocalizedString("catalog_section_default", comment: ""))) {
                        ForEach(self.viewModel.defaultCatalogSources, id: \.id) { catalogSource in
                            self.row(for: catalogSource)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("catalog_title", comment: ""))
            .task {
                await self.viewModel.loadCatalogSourcesIfNeeded()
            }
            .refreshable {
                await self.viewModel.refreshCatalogSources()
                self.failedSourceIDs.removeAll()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                }
            }
        }
    }

    /// 中文注释：个人分组 = 当前用户成功生成的规则（按 `/outcomes` 的 catalogSourceId 挑出）
    /// + 失败任务的成因说明；未登录时给登录提示，登录了但没有任务时不显示该分组。
    @ViewBuilder
    private var personalSection: some View {
        if self.viewModel.isPersonalCatalogSignInRequired {
            Section(header: Text(NSLocalizedString("catalog_section_personal", comment: ""))) {
                Text(NSLocalizedString("catalog_personal_sign_in_hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if self.viewModel.personalCatalogSources.isEmpty == false
            || self.viewModel.failedGenerationOutcomes.isEmpty == false {
            Section(
                header: Text(NSLocalizedString("catalog_section_personal", comment: "")),
                footer: Text(NSLocalizedString("catalog_personal_retention_hint", comment: ""))
            ) {
                ForEach(self.viewModel.personalCatalogSources, id: \.id) { catalogSource in
                    VStack(alignment: .leading, spacing: 4) {
                        self.row(for: catalogSource)
                        if let remainingText: String = self.remainingText(for: catalogSource) {
                            Text(remainingText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await self.viewModel.deletePersonalRule(catalogSourceID: catalogSource.id)
                            }
                        } label: {
                            Label(NSLocalizedString("catalog_personal_delete", comment: ""), systemImage: "trash")
                        }
                    }
                }
                ForEach(self.viewModel.failedGenerationOutcomes, id: \.jobID) { outcome in
                    FailedGenerationOutcomeRowView(outcome: outcome)
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
        }
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

    private func row(for catalogSource: CatalogSource) -> some View {
        return CatalogSourceRowView(
            catalogSource: catalogSource,
            subtitleURL: self.viewModel.catalogEntryURL(for: catalogSource) ?? catalogSource.baseURL,
            isAdded: self.viewModel.isCatalogSourceAdded(catalogSource),
            hasUpdate: self.viewModel.catalogSourceHasRuleUpdate(catalogSource),
            isAdding: self.addingSourceIDs.contains(catalogSource.id),
            failureMessage: self.failedSourceIDs.contains(catalogSource.id)
                ? (self.viewModel.catalogSourceAddFailureMessages[catalogSource.id]
                    ?? NSLocalizedString("catalog_add_failed", comment: ""))
                : nil,
            addAction: {
                self.add(catalogSource)
            }
        )
    }

    private func add(_ catalogSource: CatalogSource) {
        let isUpdate: Bool = self.viewModel.isCatalogSourceAdded(catalogSource)
        if self.addingSourceIDs.contains(catalogSource.id)
            || (isUpdate && self.viewModel.catalogSourceHasRuleUpdate(catalogSource) == false) {
            return
        }

        self.addingSourceIDs.insert(catalogSource.id)
        self.failedSourceIDs.remove(catalogSource.id)

        Task {
            // 中文注释：更新与首次添加走同一条路——`AddCatalogSourceUseCase` 遇到同 id 直接保存新规则，
            // createdAt / enabled / origin 与阅读历史都不动。更新完留在目录页，让那一行变回「已添加」。
            let didAdd: Bool = await self.viewModel.addCatalogSource(
                catalogSource,
                shouldPresentError: false
            )
            await MainActor.run {
                self.addingSourceIDs.remove(catalogSource.id)
                if didAdd {
                    if isUpdate == false {
                        self.dismiss()
                    }
                } else {
                    self.failedSourceIDs.insert(catalogSource.id)
                }
            }
        }
    }
}

/// 失败的生成任务：入口 URL + 面向用户的成因（`reason`），有细分时再补一句（`reasonDetail`）。
private struct FailedGenerationOutcomeRowView: View {
    let outcome: VideoGenerationOutcome

    @State private var isShowingGuide: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.outcome.entryURL ?? self.outcome.jobID.uuidString)
                .font(.body)
                .lineLimit(1)
            Text(VideoGenerationOutcomeText.reasonText(for: self.outcome))
                .font(.caption)
                .foregroundColor(.secondary)
            if let detail: String = VideoGenerationOutcomeText.reasonDetailText(for: self.outcome) {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            // 中文注释：入口页资格拒因（`BC-PAGE-060` 的四种）说的就是「这一页不合格」，
            // 下一步是换一个合格的页面——把教程接在这里，用户不必自己去添加来源里翻。
            if VideoGenerationOutcomeText.isEntryPageRejection(self.outcome) {
                Button(NSLocalizedString("entry_guide_open_from_failure", comment: "")) {
                    self.isShowingGuide = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .listRowSeparatorAlignedToRowLeading()
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

/// 成因 → 本地化文案。键与推送的 `push_generation_failed_*` 同一套 reason 后缀，
/// 两条通道对同一次失败说同一句话；未知值降级到通用文案。
enum VideoGenerationOutcomeText {
    static let knownReasons: Set<String> = [
        "siteRejectedFetcher", "siteNotSupported", "siteUnreachable",
        "inputInvalid", "evidenceInsufficient", "temporaryFailure"
    ]
    // `BC-PAGE-060` 的四种入口页拒因（服务端 `BC-PREFLIGHT-056` 2026-09-20 修订）并进这张表。
    // 不在表里的细分一律不显示，只留 `reason` 的通用文案——服务端先于 App 上线新值是常态。
    static let knownReasonDetails: Set<String> = Set<String>([
        "noPlaybackCarrier", "episodeLayoutUnsupported",
        // `BC-IMPL-139`：终端页已取到却没有可识别的内容载体（按 kind 中立措辞）。
        "terminalPagesWithoutCarrier"
    ]).union(Self.entryPageRejectionDetails)

    static func reasonText(for outcome: VideoGenerationOutcome) -> String {
        guard let reason: String = outcome.reason, Self.knownReasons.contains(reason) else {
            return NSLocalizedString("video_generation_outcome_failed_unknown", comment: "")
        }
        return NSLocalizedString("video_generation_outcome_failed_\(reason)", comment: "")
    }

    /// `BC-PAGE-060` 的四种入口页拒因——它们都指向同一件事：换一个合格的入口页。
    static let entryPageRejectionDetails: Set<String> = [
        "entryPageWithoutPagination", "entryPageMultipleListFamilies",
        "entryPageNoListFamily", "entryPageShapeAmbiguous"
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

private struct CatalogSourceRowView: View {
    let catalogSource: CatalogSource
    let subtitleURL: String
    let isAdded: Bool
    let hasUpdate: Bool
    let isAdding: Bool
    let failureMessage: String?
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.catalogSource.name)
                    .font(.body)
                Text(self.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let failureMessage: String = self.failureMessage {
                    Text(failureMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer(minLength: 12)

            self.trailingControl
        }
        // 中文注释：「已添加」那行的 Label 会把分隔线推到右侧只剩一小截（09-05 真机截图），
        // 钉到行的 leading 让分隔线通栏；取值点在 `ListRowSeparatorAlignment.swift`。
        .listRowSeparatorAlignedToRowLeading()
    }

    @ViewBuilder
    private var trailingControl: some View {
        if self.isAdding {
            ProgressView()
        } else if self.isAdded && self.hasUpdate {
            // 中文注释：目录里的规则比本地新——点一下覆盖本地规则，不必删掉重加。
            Button(action: self.addAction) {
                Label(NSLocalizedString("catalog_update_rule", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Update \(self.catalogSource.name)")
        } else if self.isAdded {
            Label("Added", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Button(
                action: self.addAction,
                label: {
                    Image(systemName: "plus.circle")
                }
            )
            .accessibilityLabel("Add \(self.catalogSource.name)")
        }
    }

    private var subtitle: String {
        return "\(self.kindTitle) · \(self.subtitleURL)"
    }

    private var kindTitle: String {
        switch self.catalogSource.kind {
        case .comic:
            return NSLocalizedString("Comics", comment: "")
        case .video:
            return NSLocalizedString("Video", comment: "")
        case .book:
            return NSLocalizedString("Books", comment: "")
        }
    }
}
