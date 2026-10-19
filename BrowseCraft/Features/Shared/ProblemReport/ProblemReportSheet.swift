import SwiftUI

// 中文注释：报告问题面板（docs/design/Problem-Report-Design.md 第四节）。版式同网址输入页的重新生成面板，颜色只取 `CatalogPalette`。
// 只在用户点「发送」时发出（`BCA-OBS-018`）；发送失败不自动重试，只给「再试一次」，已填内容不丢。

struct ProblemReportSheet: View {
    let context: ProblemReportContext
    let onClose: () -> Void

    @Environment(\.problemReportSubmitter) private var submitter: SubmitProblemReportUseCase?
    @State private var scope: ProblemReportScope
    @State private var lineID: String?
    @State private var episodeID: String?
    @State private var problemType: ProblemReportProblemType?
    @State private var note: String = ""
    @State private var includesLogs: Bool = true
    @State private var showsDetails: Bool = false
    @State private var isPickingEpisode: Bool = false
    @State private var phase: Phase = .editing

    private struct DetailRow: Hashable {
        let label: String
        let value: String
    }

    private enum Phase: Equatable {
        case editing
        case sending
        case sent(reportID: String)
        case failed(ProblemReportFailureCode)
    }

    init(context: ProblemReportContext, onClose: @escaping () -> Void) {
        self.context = context
        self.onClose = onClose
        let startsWithContent: Bool = context.entry == .pageMenu
            && context.supportsContent
            && RuleFailureSnapshotStore.shared.latest(points: context.contentFailurePoints, sourceID: context.source.id) != nil
        let initialScope: ProblemReportScope = startsWithContent ? .content : context.primaryScope
        _scope = State(initialValue: initialScope)
        _lineID = State(initialValue: context.defaultLineID)
        _episodeID = State(initialValue: context.defaultEpisodeID)
        _problemType = State(initialValue: context.entry == .failureState ? .loadFailed : nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if case .sent(let reportID) = self.phase {
                    self.sentView(reportID: reportID)
                } else {
                    self.form
                }
            }
            .padding(.bottom, 16)
        }
        .background(CatalogPalette.pageBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .interactiveDismissDisabled(self.phase == .sending)
        .analyticsScreen(.problemReport)
        .sheet(isPresented: self.$isPickingEpisode) {
            self.episodePicker
        }
    }

    // MARK: - 表单

    @ViewBuilder
    private var form: some View {
        self.header
        self.objectCard
            .padding(.horizontal, 20)
            .padding(.top, 16)
        if self.context.supportsContent {
            self.areaPicker
                .padding(.horizontal, 20)
                .padding(.top, 16)
        }
        if self.scope == .content, let episode: ProblemReportEpisode = self.selectedEpisode {
            self.episodeRow(episode)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        if self.snapshot?.looksSiteSide == true {
            Text(NSLocalizedString("problem_report_site_side_hint", comment: "站点侧提示"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 14)
        }
        self.typeChips
        self.noteField
        self.detailsSection
        if case .failed(let code) = self.phase {
            Text(NSLocalizedString(
                code == .rateLimited ? "problem_report_failed_rate_limited" : "problem_report_failed",
                comment: "发送失败"
            ))
            .font(.footnote)
            .foregroundStyle(CatalogPalette.warning)
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        self.sendButton
            .padding(.horizontal, 20)
            .padding(.top, 18)
        Button(NSLocalizedString("problem_report_cancel", comment: "取消"), action: self.onClose)
            .font(.body)
            .foregroundStyle(CatalogPalette.addAction)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.top, 4)
            .disabled(self.phase == .sending)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CatalogPalette.settingsIcon)
                    .frame(width: 28, height: 28)
                    .background(CatalogPalette.settingsIconFill, in: Circle())
                    .accessibilityHidden(true)
                Text(NSLocalizedString("problem_report_title", comment: "面板标题"))
                    .font(.title2.weight(.heavy))
            }
            Text(NSLocalizedString("problem_report_message", comment: "面板说明"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var objectCard: some View {
        let style: CatalogKindStyle = CatalogKindStyle.of(self.context.source)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: self.context.isAudiobook ? "headphones" : style.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(style.accent)
                    .accessibilityHidden(true)
                Text("\(self.context.source.name) · \(self.context.pageName)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            if self.context.entry == .failureState, let message: String = self.context.failureMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(CatalogPalette.warning)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var areaPicker: some View {
        Picker(NSLocalizedString("problem_report_area_title", comment: "问题出在哪"), selection: self.$scope) {
            Text(NSLocalizedString("problem_report_area_detail", comment: "详情与目录"))
                .tag(ProblemReportScope.detail)
            Text(ProblemReportOptions.contentAreaTitle(kind: self.context.kind))
                .tag(ProblemReportScope.content)
        }
        .pickerStyle(.segmented)
        .disabled(self.context.entry == .failureState || self.phase == .sending)
        .onChange(of: self.scope) { _, _ in
            if let problemType: ProblemReportProblemType = self.problemType, self.options.contains(problemType) == false {
                self.problemType = nil
            }
        }
    }

    private func episodeRow(_ episode: ProblemReportEpisode) -> some View {
        Button {
            self.isPickingEpisode = true
        } label: {
            HStack(spacing: 6) {
                Text(ProblemReportOptions.episodeRowTitle(kind: self.context.kind))
                    .foregroundStyle(.secondary)
                Text(self.episodeLabel(episode))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(self.phase == .sending)
    }

    private var typeChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("problem_report_type_title", comment: "问题类型"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            VideoEpisodeFlowLayout(spacing: 8) {
                ForEach(self.options, id: \.self) { type in
                    let isSelected: Bool = self.problemType == type
                    Button {
                        self.problemType = type
                    } label: {
                        Text(ProblemReportOptions.title(
                            for: type,
                            scope: self.scope,
                            kind: self.context.kind,
                            isAudiobook: self.context.isAudiobook
                        ))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? CatalogPalette.onAction : Color.primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(isSelected ? CatalogPalette.addAction : CatalogPalette.cardBackground, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .disabled(self.phase == .sending)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("problem_report_note_title", comment: "补充说明"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(
                NSLocalizedString("problem_report_note_placeholder", comment: "补充说明占位"),
                text: self.$note,
                axis: .vertical
            )
            .lineLimit(2...5)
            .font(.subheadline)
            .padding(12)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: self.note) { _, newValue in
                if newValue.count > SubmitProblemReportUseCase.noteMaxCharacters {
                    self.note = String(newValue.prefix(SubmitProblemReportUseCase.noteMaxCharacters))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .disabled(self.phase == .sending)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showsDetails.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(NSLocalizedString("problem_report_details_summary", comment: "将一并发送"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: self.showsDetails ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if self.showsDetails {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(self.detailRows, id: \.self) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(row.value)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                    Toggle(NSLocalizedString("problem_report_include_logs", comment: "附带诊断日志"), isOn: self.$includesLogs)
                        .font(.caption)
                        .tint(CatalogPalette.addAction)
                }
                .padding(12)
                .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var sendButton: some View {
        Button(action: self.send) {
            HStack(spacing: 8) {
                if self.phase == .sending {
                    ProgressView()
                        .tint(CatalogPalette.onAction)
                }
                Text(NSLocalizedString(
                    self.isRetry ? "problem_report_retry" : "problem_report_send",
                    comment: "发送"
                ))
                .font(.body.weight(.semibold))
            }
            .foregroundStyle(CatalogPalette.onAction)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(CatalogPalette.addAction.opacity(self.canSend ? 1 : 0.4), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(self.canSend == false)
    }

    // MARK: - 发送成功

    private func sentView(reportID: String) -> some View {
        VStack(spacing: 16) {
            StatusCardView(
                systemImage: "checkmark",
                title: NSLocalizedString("problem_report_sent_title", comment: "已发送"),
                message: NSLocalizedString("problem_report_sent_message", comment: "联系我们时报这个编号")
            ) {
                Button {
                    UIPasteboard.general.string = reportID
                } label: {
                    Label(reportID, systemImage: "doc.on.doc")
                        .font(.headline.monospaced())
                        .foregroundStyle(CatalogPalette.addAction)
                }
                .buttonStyle(.plain)
                .accessibilityHint(NSLocalizedString("problem_report_copy_hint", comment: "读屏：点一下复制编号"))
            }
            Button(action: self.onClose) {
                Text(NSLocalizedString("problem_report_done", comment: "完成"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CatalogPalette.onAction)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(CatalogPalette.addAction, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
    }

    // MARK: - 选集

    private var episodePicker: some View {
        NavigationStack {
            List {
                ForEach(self.context.lines) { line in
                    Section {
                        ForEach(line.episodes) { episode in
                            Button {
                                self.lineID = line.id
                                self.episodeID = episode.id
                                self.isPickingEpisode = false
                            } label: {
                                HStack {
                                    Text(episode.title)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                    if line.id == self.lineID, episode.id == self.episodeID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(CatalogPalette.addAction)
                                    }
                                }
                            }
                        }
                    } header: {
                        if let title: String = line.title {
                            Text(title)
                        }
                    }
                }
            }
            .navigationTitle(ProblemReportOptions.episodeRowTitle(kind: self.context.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("problem_report_cancel", comment: "取消")) {
                        self.isPickingEpisode = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - 数据

    private var options: [ProblemReportProblemType] {
        return ProblemReportOptions.types(scope: self.scope, kind: self.context.kind, isAudiobook: self.context.isAudiobook)
    }

    private var selectedLine: ProblemReportEpisodeLine? {
        return self.context.lines.first { $0.id == self.lineID } ?? self.context.lines.first
    }

    private var selectedEpisode: ProblemReportEpisode? {
        guard let line: ProblemReportEpisodeLine = self.selectedLine else {
            return nil
        }
        return line.episodes.first { $0.id == self.episodeID } ?? line.episodes.first
    }

    private func episodeLabel(_ episode: ProblemReportEpisode) -> String {
        guard self.context.defaultEpisodeIsFromHistory,
              episode.id == self.context.defaultEpisodeID,
              self.selectedLine?.id == self.context.defaultLineID else {
            return episode.title
        }
        let key: String
        if self.context.isAudiobook {
            key = "problem_report_episode_last_listen"
        } else if self.context.kind == .video {
            key = "problem_report_episode_last_watch"
        } else {
            key = "problem_report_episode_last_read"
        }
        return String(format: NSLocalizedString(key, comment: "上次看到 / 读到 / 听到 %@"), episode.title)
    }

    private var snapshot: RuleFailureSnapshot? {
        let points: Set<RuleFailurePoint> = self.scope == .content
            ? self.context.contentFailurePoints
            : self.context.primaryFailurePoints
        return RuleFailureSnapshotStore.shared.latest(points: points, sourceID: self.context.source.id)
    }

    private var canSend: Bool {
        return self.submitter != nil && self.problemType != nil && self.phase != .sending
    }

    private var isRetry: Bool {
        if case .failed = self.phase {
            return true
        }
        return false
    }

    private var target: (url: String?, title: String?, chapterTitle: String?, chapterIndex: Int?) {
        guard self.scope == .content, let episode: ProblemReportEpisode = self.selectedEpisode else {
            return (self.context.targetURL, self.context.targetTitle, nil, nil)
        }
        let chapterTitle: String = self.selectedLine?.title.map { "\($0) · \(episode.title)" } ?? episode.title
        return (episode.url ?? self.context.targetURL, self.context.targetTitle, chapterTitle, episode.index)
    }

    private var detailRows: [DetailRow] {
        let target: (url: String?, title: String?, chapterTitle: String?, chapterIndex: Int?) = self.target
        var rows: [DetailRow] = [
            DetailRow(
                label: NSLocalizedString("problem_report_detail_page", comment: "页面"),
                value: "\(self.context.source.name) · \(self.context.pageName)"
            )
        ]
        if let url: String = ProblemReportURLSanitizer.clean(target.url) {
            rows.append(DetailRow(label: NSLocalizedString("problem_report_detail_url", comment: "网址"), value: url))
        }
        if let title: String = target.title {
            rows.append(DetailRow(label: NSLocalizedString("problem_report_detail_title", comment: "作品"), value: title))
        }
        if let chapterTitle: String = target.chapterTitle {
            rows.append(DetailRow(label: ProblemReportOptions.episodeRowTitle(kind: self.context.kind), value: chapterTitle))
        }
        rows.append(DetailRow(
            label: NSLocalizedString("problem_report_detail_rule", comment: "规则版本"),
            value: NSLocalizedString("problem_report_detail_rule_value", comment: "目录下发的规则指纹")
        ))
        rows.append(DetailRow(
            label: NSLocalizedString("problem_report_detail_failure", comment: "失败信息"),
            value: self.snapshot.map { "\($0.point.rawValue) · \($0.errorCase ?? $0.kind)" }
                ?? NSLocalizedString("problem_report_detail_failure_none", comment: "最近没有失败")
        ))
        rows.append(DetailRow(
            label: NSLocalizedString("problem_report_detail_device", comment: "设备"),
            value: "\(DiagnosticDeviceInfo.deviceModel) · \(DiagnosticDeviceInfo.systemVersion) · \(DiagnosticDeviceInfo.appVersion)"
        ))
        return rows
    }

    // MARK: - 发送

    private func send() {
        guard let submitter: SubmitProblemReportUseCase = self.submitter,
              let problemType: ProblemReportProblemType = self.problemType,
              self.phase != .sending else {
            return
        }
        let scope: ProblemReportScope = self.scope
        let target: (url: String?, title: String?, chapterTitle: String?, chapterIndex: Int?) = self.target
        let draft: ProblemReportDraft = ProblemReportDraft(
            clientReportID: self.context.id,
            entry: self.context.entry,
            scope: scope,
            problemType: problemType,
            note: self.note,
            screen: self.context.screen,
            source: self.context.source,
            targetURL: target.url,
            targetTitle: target.title,
            chapterTitle: target.chapterTitle,
            chapterIndex: target.chapterIndex,
            categoryKey: scope == .list ? self.context.categoryKey : nil,
            failure: self.snapshot,
            includesLogs: self.includesLogs
        )
        let entry: ProblemReportEntry = self.context.entry
        self.phase = .sending
        Task {
            do {
                let receipt: ProblemReportReceipt = try await submitter.execute(draft)
                AppAnalytics.shared.logProblemReportSubmitted(scope: scope, problemType: problemType, entry: entry, failure: nil)
                self.phase = .sent(reportID: receipt.reportID)
            } catch is CancellationError {
                // 不记：面板被关掉、发送随之取消，没有发出也不算失败
                self.phase = .editing
            } catch {
                // 失败已由用例记 error（problem-report-failed），这里只换成界面状态
                let code: ProblemReportFailureCode = (error as? ProblemReportSubmissionError) == .rateLimited
                    ? .rateLimited
                    : .sendFailed
                AppAnalytics.shared.logProblemReportSubmitted(scope: scope, problemType: problemType, entry: entry, failure: code)
                self.phase = .failed(code)
            }
        }
    }
}
