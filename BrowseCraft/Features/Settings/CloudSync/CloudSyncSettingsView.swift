import SwiftUI

// 中文注释：云同步页（`docs/design/Cloud-Sync-Page-Redesign-Design.md`）：从设置页「同步与存储 › 云同步」推进来；
// 状态卡 + 开关 + 同步的内容 + 上次同步。页面上不放按钮，重新检查 iCloud、重新关联、同步与重试都由下拉承担。
@MainActor
struct CloudSyncSettingsView: View {
    @Bindable var viewModel: CloudSyncSettingsViewModel
    /// 中文注释：设置页传入的 Portal 登录态。未登录时开关只能关不能开（关联协调器里还有一道同样的门禁，这里只是不让用户白点）。
    var isPortalSignedIn: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CloudSyncStatusCardView(status: self.viewModel.statusCard)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                self.toggleGroup

                self.contentGroup

                self.lastSyncSection
            }
            .padding(.bottom, 24)
        }
        .background(CatalogPalette.pageBackground)
        .navigationTitle(NSLocalizedString("Cloud Sync", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        // 中文注释：二级页隐藏底栏，左上返回是唯一出口（用户裁定，与 coin 记录页、缓存页同一做法）。
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            // 中文注释：下拉的任务会在页面状态变化重绘时被系统取消，同步跟着被取消；
            // 放进独立任务里跑，下拉只等它结束。
            await Task {
                await self.viewModel.refreshFromPull()
            }.value
        }
        .task {
            await self.viewModel.start()
            self.viewModel.refreshSyncedContentSummary()
        }
        .sheet(item: self.setupRequestBinding) { request in
            self.setupSheet(for: request)
        }
    }

    // MARK: - 开关

    /// 中文注释：未登录且同步还没开才拦；已开着的开关要留给用户关掉。
    private var requiresPortalSignIn: Bool {
        return self.isPortalSignedIn == false && self.viewModel.isCloudSyncEnabled == false
    }

    private var toggleGroup: some View {
        SettingsCardGroup(
            title: nil,
            footer: self.requiresPortalSignIn
                ? NSLocalizedString("cloud_sync_portal_sign_in_required", comment: "开启云同步需要先登录账号")
                : NSLocalizedString("cloud_sync_toggle_footer", comment: "关闭后不会删除任何数据")
        ) {
            Toggle(isOn: self.cloudSyncEnabledBinding) {
                Text(NSLocalizedString("Cloud Sync", comment: ""))
                    .font(.body)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .disabled(self.viewModel.canChangeCloudSyncEnabled == false || self.requiresPortalSignIn)
            .onChange(of: self.viewModel.isCloudSyncEnabled) { _, newValue in
                AppAnalytics.shared.logSettingChanged(
                    name: "cloud_sync",
                    value: String(newValue)
                )
            }
        }
        .padding(.top, 20)
    }

    // MARK: - 同步的内容

    /// 中文注释：三行都同步；历史与阅读进度同步的是每部作品看到哪里（`docs/design/History-Resume-Sync-Design.md`），按作品计数。
    private var contentGroup: some View {
        SettingsCardGroup(
            title: NSLocalizedString("cloud_sync_content_section", comment: "同步的内容"),
            footer: NSLocalizedString("cloud_sync_content_footer", comment: "内置来源不占用 iCloud")
        ) {
            CloudSyncContentRow(
                systemImage: "rectangle.stack.fill",
                title: NSLocalizedString("cloud_sync_content_sources", comment: "来源"),
                detail: self.countText(self.viewModel.syncedContentSummary?.sourceCount)
            )
            SettingsRowSeparator()
            CloudSyncContentRow(
                systemImage: "heart.fill",
                title: NSLocalizedString("cloud_sync_content_favorites", comment: "收藏"),
                detail: self.countText(self.viewModel.syncedContentSummary?.favoriteItemCount)
            )
            SettingsRowSeparator()
            CloudSyncContentRow(
                systemImage: "clock.fill",
                title: NSLocalizedString("cloud_sync_content_history", comment: "历史与阅读进度"),
                detail: self.viewModel.syncedHistoryWorkCount.map { count in
                    String(format: NSLocalizedString("cloud_sync_content_work_count", comment: "%d 部"), count)
                }
            )
        }
    }

    private func countText(_ count: Int?) -> String? {
        guard let count: Int = count else {
            return nil
        }
        return String(
            format: NSLocalizedString("cloud_sync_content_count", comment: "%d 个"),
            count
        )
    }

    // MARK: - 上次同步

    /// 中文注释：收成一行小字；云端删除在本机生效的条数并入「下载」。只有上传失败才追加警示色一句——
    /// 「跳过」里混着正常合并时本机较新而不采用云端的记录，不是问题，不显示。
    @ViewBuilder
    private var lastSyncSection: some View {
        if let result: CloudSyncRunResult = self.viewModel.lastResult {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(
                    format: NSLocalizedString("cloud_sync_last_sync", comment: "上次同步 时间 · 上传 N · 下载 N"),
                    self.lastSyncTimeText(result.finishedAt),
                    result.uploadedCount,
                    result.downloadedCount + result.deletedCount
                ))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

                if result.failedCount > 0 {
                    Text(String(
                        format: NSLocalizedString("cloud_sync_last_sync_failed", comment: "N 项未能上传"),
                        result.failedCount
                    ))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(CatalogPalette.warning)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    /// 今天的只写时刻，更早的带日期。
    private func lastSyncTimeText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - 绑定

    private var cloudSyncEnabledBinding: Binding<Bool> {
        return Binding(
            get: {
                return self.viewModel.isCloudSyncEnabled
            },
            set: { enabled in
                Task {
                    await self.viewModel.setCloudSyncEnabled(enabled)
                }
            }
        )
    }

    private var setupRequestBinding: Binding<CloudSyncSettingsViewModel.SetupRequest?> {
        return Binding(
            get: {
                return self.viewModel.setupRequest
            },
            set: { request in
                if request == nil {
                    self.viewModel.dismissSetupRequest()
                }
            }
        )
    }

    @ViewBuilder
    private func setupSheet(
        for request: CloudSyncSettingsViewModel.SetupRequest
    ) -> some View {
        switch request {
        case .firstEnable(let firstEnableRequest):
            CloudSyncFirstEnableSheet(
                viewModel: self.viewModel,
                request: firstEnableRequest
            )
        }
    }
}

/// 状态卡：56pt 圆形图标 + 标题 + 一句说明；进行中带转圈，异常换警示色描边并提示「下拉可重试」。
/// 样式与来源页「iCloud 首次恢复」卡（`CloudSyncInitialRestoreView`）一致。
private struct CloudSyncStatusCardView: View {
    let status: CloudSyncSettingsViewModel.StatusCard

    var body: some View {
        // 中文注释：卡片本体是共用的 `StatusCardView`（网址输入页的结论卡与结果卡同一套）；这里只提供取值与两段附加小字。
        StatusCardView(
            systemImage: self.systemImage,
            title: self.title,
            message: self.message,
            tone: self.tone,
            isInProgress: self.isInProgress
        ) {
            if case .failed(_, let detail?) = self.status {
                Text(verbatim: detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if self.status.isWarning {
                Label(NSLocalizedString("cloud_restore_pull_to_retry", comment: ""), systemImage: "arrow.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tone: StatusCardTone {
        if self.status.isWarning {
            return .warning
        }
        if self.status == .off {
            return .neutral
        }
        return .action
    }

    private var isInProgress: Bool {
        switch self.status {
        case .checking, .synchronizing:
            return true
        default:
            return false
        }
    }

    private var systemImage: String {
        switch self.status {
        case .checking, .synchronizing, .off:
            return "icloud"
        case .signInRequired:
            return "icloud.slash"
        case .restricted, .temporarilyUnavailable, .statusUnavailable:
            return "exclamationmark.icloud"
        case .accountMismatch, .verificationRequired:
            return "person.crop.circle.badge.exclamationmark"
        case .failed:
            return "exclamationmark.triangle"
        case .synchronized:
            return "checkmark.icloud"
        }
    }

    private var title: String {
        switch self.status {
        case .checking:
            return NSLocalizedString("cloud_sync_status_checking_title", comment: "正在检查 iCloud")
        case .signInRequired:
            return NSLocalizedString("cloud_sync_status_sign_in_title", comment: "这台设备没有登录 iCloud")
        case .restricted:
            return NSLocalizedString("cloud_sync_status_restricted_title", comment: "iCloud 受到限制")
        case .temporarilyUnavailable:
            return NSLocalizedString("cloud_sync_status_temporary_title", comment: "iCloud 暂时不可用")
        case .statusUnavailable:
            return NSLocalizedString("cloud_sync_status_unknown_title", comment: "无法检查 iCloud")
        case .accountMismatch:
            return NSLocalizedString("cloud_sync_status_mismatch_title", comment: "账号不一致")
        case .verificationRequired:
            return NSLocalizedString("cloud_sync_status_verify_title", comment: "需要重新验证账号")
        case .synchronizing:
            return NSLocalizedString("cloud_sync_status_syncing_title", comment: "正在同步")
        case .failed:
            return NSLocalizedString("cloud_sync_status_failed_title", comment: "同步没有完成")
        case .synchronized:
            return NSLocalizedString("cloud_sync_status_synced_title", comment: "已同步到 iCloud")
        case .off:
            return NSLocalizedString("cloud_sync_status_off_title", comment: "云同步未开启")
        }
    }

    private var message: String {
        switch self.status {
        case .checking:
            return NSLocalizedString("cloud_sync_status_checking_message", comment: "")
        case .signInRequired:
            return NSLocalizedString("cloud_sync_status_sign_in_message", comment: "")
        case .restricted:
            return NSLocalizedString("cloud_sync_status_restricted_message", comment: "")
        case .temporarilyUnavailable:
            return NSLocalizedString("cloud_sync_status_temporary_message", comment: "")
        case .statusUnavailable:
            return NSLocalizedString("cloud_sync_status_unknown_message", comment: "")
        case .accountMismatch:
            return NSLocalizedString("cloud_sync_status_mismatch_message", comment: "")
        case .verificationRequired:
            return NSLocalizedString("cloud_sync_status_verify_message", comment: "")
        case .synchronizing:
            return NSLocalizedString("cloud_sync_status_syncing_message", comment: "")
        case .failed(let message, _):
            return message ?? NSLocalizedString("cloud_sync_status_failed_message", comment: "本机的改动已保留")
        case .synchronized:
            return NSLocalizedString("cloud_sync_status_synced_message", comment: "")
        case .off:
            return NSLocalizedString("cloud_sync_status_off_message", comment: "")
        }
    }
}

/// 「同步的内容」里的一行：32pt 图标方块 + 标题 + 右侧条数。
private struct CloudSyncContentRow: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CatalogPalette.settingsIcon)
                .frame(width: 32, height: 32)
                .background(
                    CatalogPalette.settingsIconFill,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(self.title)
                .font(.body)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let detail: String = self.detail {
                Text(detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// 首次开启窗口：只改了外观与文案，「合并本机数据」与「只用 iCloud 数据」两个选择的含义不变。
@MainActor
private struct CloudSyncFirstEnableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: CloudSyncSettingsViewModel
    let request: CloudSyncSettingsViewModel.FirstEnableRequest

    @State private var submittingDecision: CloudAccountLocalDataDecision?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("cloud_sync_first_title", comment: "首次云同步"))
                        .font(.largeTitle.weight(.heavy))
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)

                    Text(NSLocalizedString("cloud_sync_first_message", comment: "云同步存什么、不存什么"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    if self.request.localDataSummary.hasMergeableData {
                        self.mergeChoices
                    } else {
                        self.enableOnly
                    }

                    if let errorMessage: String = self.viewModel.actionErrorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(CatalogPalette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .padding(.top, 10)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(CatalogPalette.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(self.isSubmitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) {
                        self.viewModel.cancelFirstEnable()
                        self.dismiss()
                    }
                    .disabled(self.isSubmitting)
                }
            }
        }
    }

    private var isSubmitting: Bool {
        return self.submittingDecision != nil
    }

    /// 中文注释：小标题的条数与页面「同步的内容」同一口径（不含删除标记）；`localDataSummary` 把删除标记也算在内，
    /// 只用来决定走不走合并这条路，不拿来显示。
    private var mergeChoices: some View {
        let summary: CloudAccountPartitionSummary =
            self.viewModel.syncedContentSummary ?? self.request.localDataSummary
        return VStack(alignment: .leading, spacing: 0) {
            Text(String(
                format: NSLocalizedString("cloud_sync_first_local_data", comment: "本机已有 N 个来源、N 个收藏"),
                summary.sourceCount,
                summary.favoriteItemCount
            ))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 8)

            VStack(spacing: 12) {
                self.choiceCard(
                    decision: .mergeLocalData,
                    title: NSLocalizedString("cloud_sync_first_merge_title", comment: "合并本机数据"),
                    message: NSLocalizedString("cloud_sync_first_merge_message", comment: ""),
                    systemImage: "arrow.triangle.merge"
                )
                self.choiceCard(
                    decision: .useCloudDataOnly,
                    title: NSLocalizedString("cloud_sync_first_cloud_only_title", comment: "只用 iCloud 数据"),
                    message: NSLocalizedString("cloud_sync_first_cloud_only_message", comment: ""),
                    systemImage: "icloud"
                )
            }
            .padding(.horizontal, 20)

            Text(NSLocalizedString("cloud_sync_first_keeps", comment: "两种选择都不会删除本机现有的数据"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 10)
        }
    }

    /// 中文注释：提交中两张卡都禁用，没被点的那张变淡，被点的那张行尾换成转圈。
    private func choiceCard(
        decision: CloudAccountLocalDataDecision,
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        let isThisSubmitting: Bool = self.submittingDecision == decision
        return SourcesEntryCardView(
            title: title,
            message: message,
            systemImage: systemImage,
            iconForeground: CatalogPalette.onAction,
            iconBackground: CatalogPalette.addAction,
            action: {
                self.submit(decision: decision)
            }
        )
        .overlay(alignment: .trailing) {
            if isThisSubmitting {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .background(CatalogPalette.cardBackground)
                    .padding(.trailing, 4)
            }
        }
        .disabled(self.isSubmitting)
        .opacity(self.isSubmitting && isThisSubmitting == false ? 0.45 : 1)
    }

    private var enableOnly: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(
                action: {
                    self.submit(decision: .useCloudDataOnly)
                },
                label: {
                    HStack(spacing: 8) {
                        if self.isSubmitting {
                            ProgressView()
                                .tint(CatalogPalette.onAction)
                        }
                        Text(NSLocalizedString("cloud_sync_first_enable", comment: "开启云同步"))
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CatalogPalette.onAction)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(CatalogPalette.addAction, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            )
            .buttonStyle(.plain)
            .disabled(self.isSubmitting)
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Text(NSLocalizedString("cloud_sync_first_empty_footer", comment: "本机没有需要合并的数据"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 10)
        }
    }

    private func submit(decision: CloudAccountLocalDataDecision) {
        guard self.isSubmitting == false else {
            return
        }
        self.submittingDecision = decision

        Task {
            await self.viewModel.confirmFirstEnable(decision: decision)
            self.submittingDecision = nil
            if self.viewModel.firstEnableRequest == nil {
                self.dismiss()
            }
        }
    }
}
