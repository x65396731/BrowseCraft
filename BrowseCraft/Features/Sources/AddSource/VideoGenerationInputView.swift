import BrowseCraftDomain
import Foundation
import SwiftUI

// 中文注释：网址输入页（`docs/design/Generation-Input-Page-Redesign-Design.md`）：贴网址 → 本机检查 → 结论 → 选取页方式、滑动提交。
// 一个阶段一张卡，任何时候页面上只有一个主控件；状态机（检查、提交、自动返回）与重设计前相同。

struct VideoGenerationInputView: View {
    @Bindable var viewModel: SourcesViewModel
    /// 中文注释：预检是中性的，三种 kind 走同一套输入与判定；`sourceKind` 只决定标题文案与提交给服务端的生成链。
    let sourceKind: RuleGenerationSourceKind
    /// 中文注释：这一屏结束时交回宿主决定落点——提交成功自动返回、按「关闭」、下滑关掉，
    /// 三条出口共用这一个回调，三种关法落在同一页；关闭哪几层 sheet 是 `AddSourceView` 的事。
    let onFinished: () -> Void

    @State private var siteURL: String = ""
    @State private var result: VideoGenerationInputPreflight?
    @State private var errorMessage: String?
    @State private var assessmentTask: Task<Void, Never>?
    @State private var assessmentID: UUID?
    @State private var isChecking: Bool = false
    /// 中文注释：取页档位（`BC-ACQ-071`）：用户在提交前自选，缺省普通档。
    @State private var acquisitionTier: GenerationAcquisitionTier = .normal
    @State private var submissionState: VideoGenerationTaskSubmissionState = .idle
    @State private var submissionTask: Task<Void, Never>?
    @State private var returnTask: Task<Void, Never>?
    @State private var isShowingGuide: Bool = false

    /// 中文注释：提交成功后停留这么久再回来源页——让「生成任务已提交」这句确认被看见，
    /// 又不必让用户自己点两层关闭。
    private static let submittedReturnDelay: Duration = .milliseconds(1200)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.titleRow
                    if self.showsIntro {
                        Text(NSLocalizedString("generation_input_intro", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                    self.urlCard
                        .padding(.horizontal, 20)
                        .padding(.top, self.showsIntro ? 16 : 12)
                    if let errorMessage: String = self.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(CatalogPalette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }
                    if self.showsIntro {
                        // 中文注释：引导屏首次必过之后就不再拦路（`EntryPageGuide.seenVersionKey`），这一行是它的常驻回看入口。
                        // 叠一层 sheet 而不是退回上一页——退回会触发本视图的 `onDisappear`，那条绑着 `onFinished()`。
                        Button(NSLocalizedString("entry_guide_reopen_link", comment: "")) {
                            self.isShowingGuide = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(CatalogPalette.addAction)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 24)
                    }
                    if self.isChecking {
                        self.progressCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        Text(NSLocalizedString("generation_input_scope_footer", comment: ""))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    } else if let result: VideoGenerationInputPreflight = self.result {
                        self.resultSection(result)
                    }
                    self.primaryControl
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }
                .padding(.bottom, 24)
            }
            .background(CatalogPalette.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("video_preflight_close_button", comment: "")) {
                        self.cancelAssessment()
                        self.onFinished()
                    }
                }
            }
            .onChange(of: self.siteURL) { _, _ in
                self.cancelAssessment()
                self.cancelSubmission()
                self.result = nil
                self.errorMessage = nil
            }
            .onDisappear {
                self.cancelAssessment()
                self.cancelSubmission()
                self.onFinished()
            }
            .sheet(isPresented: self.$isShowingGuide) {
                NavigationStack {
                    EntryPageGuideView(
                        sourceKind: self.sourceKind,
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

    // MARK: - 顶部与网址卡

    /// 出了结论或结果之后说明句与回看链接收起，省出空间给卡片。
    private var showsIntro: Bool {
        return self.result == nil && self.isChecking == false
    }

    private var kindStyle: CatalogKindStyle {
        switch self.sourceKind {
        case .video:
            return CatalogKindStyle.of(CatalogSourceKind.video)
        case .comic:
            return CatalogKindStyle.of(CatalogSourceKind.comic)
        case .book:
            return CatalogKindStyle.of(CatalogSourceKind.book)
        }
    }

    private var titleKey: String {
        switch self.sourceKind {
        case .video:
            return "generation_input_title_video"
        case .comic:
            return "generation_input_title_comic"
        case .book:
            return "generation_input_title_book"
        }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: self.kindStyle.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.kindStyle.accent)
                .frame(width: 28, height: 28)
                .background(self.kindStyle.accent.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            Text(NSLocalizedString(self.titleKey, comment: ""))
                .font(.largeTitle.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// 输入框被锁住的时候：检查中与提交中都不许改网址（改了会把当前状态清掉）。
    private var isURLLocked: Bool {
        return self.isChecking || self.submissionState.isSubmitting
    }

    private var urlCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(self.errorMessage == nil ? Color.secondary : CatalogPalette.warning)
                .accessibilityHidden(true)
            TextField(
                NSLocalizedString("generation_input_url_placeholder", comment: ""),
                text: self.$siteURL
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.go)
            .disabled(self.isURLLocked)
            .onSubmit {
                self.startAssessment()
            }
            if self.trimmedSiteURL.isEmpty {
                // 中文注释：系统粘贴按钮不弹授权；点了即填入并开始检查（2026-10-06 用户裁定）。
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted: String = strings.first else {
                        return
                    }
                    self.siteURL = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.startAssessment()
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(CatalogPalette.addAction)
            } else if self.isURLLocked == false {
                Button {
                    self.siteURL = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(CatalogPalette.fillBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("generation_input_clear", comment: ""))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(minHeight: 56)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CatalogPalette.warning.opacity(self.errorMessage == nil ? 0 : 0.6), lineWidth: 1.5)
        )
        .opacity(self.isURLLocked ? 0.6 : 1)
    }

    // MARK: - 检查进度

    private static let progressStepKeys: [String] = [
        "generation_input_step_validate",
        "generation_input_step_acquire",
        "generation_input_step_observe",
        "generation_input_step_reduce"
    ]

    private var currentProgressStep: Int {
        switch self.viewModel.videoGenerationInputProgress {
        case nil, .validatingInput?:
            return 0
        case .acquiringInput?:
            return 1
        case .observingEntryShape?:
            return 2
        case .reducingResult?:
            return 3
        }
    }

    /// 四步纵向清单：做完的打勾、当前的转圈、未到的灰。
    private var progressCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.progressStepKeys.enumerated()), id: \.offset) { index, key in
                HStack(spacing: 12) {
                    if index < self.currentProgressStep {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CatalogPalette.onAction)
                            .frame(width: 22, height: 22)
                            .background(CatalogPalette.addAction, in: Circle())
                    } else if index == self.currentProgressStep {
                        ProgressView()
                            .tint(CatalogPalette.addAction)
                            .frame(width: 22, height: 22)
                    } else {
                        Circle()
                            .strokeBorder(CatalogPalette.separator, lineWidth: 2)
                            .frame(width: 22, height: 22)
                    }
                    Text(NSLocalizedString(key, comment: ""))
                        .font(.subheadline.weight(index == self.currentProgressStep ? .semibold : .regular))
                        .foregroundStyle(index <= self.currentProgressStep ? Color.primary : Color.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
            }
        }
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 结论与结果

    @ViewBuilder
    private func resultSection(_ result: VideoGenerationInputPreflight) -> some View {
        switch self.submissionState {
        case .finished(let outcome):
            self.outcomeCard(outcome)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            if case .reused = outcome {
                Text(NSLocalizedString("generation_input_reused_hint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
        case .idle, .submitting:
            self.preflightCard(result)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            if result.canSubmit {
                // 中文注释：提交中的变淡由滑杆自己（`isEnabled`）处理，这里不再叠一层。
                self.tierGroup(result)
            } else if result.status == .rejected {
                Text(NSLocalizedString("generation_input_rejected_hint", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
        }
    }

    private func preflightCard(_ result: VideoGenerationInputPreflight) -> some View {
        // 中文注释：`BC-PREFLIGHT-063`——反爬是「可以提交」的一格，标题不能再说「证据不足」。
        let isAntiBot: Bool = result.reason == .antiBotChallenge
        let title: String
        let systemImage: String
        let tone: StatusCardTone
        if isAntiBot {
            title = NSLocalizedString("video_preflight_outcome_antibot", comment: "")
            systemImage = "checkmark.shield"
            tone = .action
        } else {
            switch result.status {
            case .accepted:
                title = NSLocalizedString("video_preflight_outcome_accepted", comment: "")
                systemImage = "checkmark.circle"
                tone = .action
            case .rejected:
                title = NSLocalizedString("video_preflight_outcome_rejected", comment: "")
                systemImage = "xmark.circle"
                tone = .warning
            case .inconclusive:
                title = NSLocalizedString("video_preflight_outcome_inconclusive", comment: "")
                systemImage = "questionmark.circle"
                tone = .warning
            }
        }
        let message: String = result.reason?.localizedDescription
            ?? NSLocalizedString("video_preflight_reason_accepted", comment: "")
        return StatusCardView(systemImage: systemImage, title: title, message: message, tone: tone) {
            if result.status == .rejected {
                Button(NSLocalizedString("entry_guide_open_from_failure", comment: "")) {
                    self.isShowingGuide = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CatalogPalette.addAction)
                .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private func outcomeCard(_ outcome: VideoGenerationTaskSubmissionOutcome) -> some View {
        switch outcome {
        case .submitted:
            StatusCardView(
                systemImage: "paperplane",
                title: NSLocalizedString("video_preflight_submitted", comment: ""),
                message: NSLocalizedString("generation_input_submitted_message", comment: "")
            ) {
                Text(NSLocalizedString("generation_input_returning", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .reused(let rule):
            StatusCardView(
                systemImage: "checkmark.seal",
                title: NSLocalizedString("video_preflight_reused", comment: ""),
                message: String(
                    format: NSLocalizedString("video_preflight_reused_detail", comment: ""),
                    rule.catalogSource.name
                )
            )
        case .authRequired:
            StatusCardView(
                systemImage: "person.crop.circle.badge.exclamationmark",
                title: NSLocalizedString("generation_input_auth_title", comment: ""),
                message: NSLocalizedString("video_preflight_submit_auth_required", comment: ""),
                tone: .warning
            )
        case .activeJobLimit:
            StatusCardView(
                systemImage: "hourglass",
                title: NSLocalizedString("generation_input_job_limit_title", comment: ""),
                message: NSLocalizedString("video_preflight_submit_active_job_limit", comment: ""),
                tone: .warning
            )
        case .previousJobActive(let entryURL):
            StatusCardView(
                systemImage: "hourglass",
                title: NSLocalizedString("generation_input_previous_job_title", comment: ""),
                message: Self.previousJobActiveMessage(entryURL: entryURL),
                tone: .warning
            )
        case .rateLimited:
            StatusCardView(
                systemImage: "clock.badge.exclamationmark",
                title: NSLocalizedString("generation_input_rate_limited_title", comment: ""),
                message: NSLocalizedString("video_preflight_submit_rate_limited", comment: ""),
                tone: .warning
            )
        case .insufficientCoins(let balance, let required):
            StatusCardView(
                systemImage: "bitcoinsign.circle",
                title: NSLocalizedString("generation_input_insufficient_title", comment: ""),
                message: String(
                    format: NSLocalizedString("video_preflight_submit_insufficient_coins", comment: ""),
                    required,
                    balance
                ),
                tone: .warning
            )
        case .failed(let code):
            StatusCardView(
                systemImage: "exclamationmark.triangle",
                title: NSLocalizedString("generation_input_failed_title", comment: ""),
                message: String(
                    format: NSLocalizedString("video_preflight_submit_failed", comment: ""),
                    code
                ),
                tone: .warning
            )
        }
    }

    // MARK: - 取页方式

    private var pricing: CoinPricing {
        return self.viewModel.coinWalletStore?.pricing ?? .placeholder
    }

    private var selectedPrice: Int {
        return self.acquisitionTier == .hard ? self.pricing.hard : self.pricing.normal
    }

    /// 中文注释：价格由服务端下发（`wallet.pricing`）；余额还没同步到时只说声明，不猜余额。没有钱包时整行不显示。
    private var balanceFooter: String? {
        guard let wallet: CoinWalletStore = self.viewModel.coinWalletStore else {
            return nil
        }
        if let balance: Int = wallet.balance {
            return String(format: NSLocalizedString("generation_input_balance_footer", comment: ""), balance)
        }
        return NSLocalizedString("generation_input_balance_unknown_footer", comment: "")
    }

    /// 中文注释：`BC-ACQ-071` ①②：档位由用户自选；预检在手机上被挑战时照样可选困难模式，但要提示
    /// 「该站在你的手机上也被拦，生成出来可能读不了」。
    private func tierGroup(_ result: VideoGenerationInputPreflight) -> some View {
        SettingsCardGroup(
            title: NSLocalizedString("video_preflight_tier_title", comment: ""),
            footer: self.balanceFooter
        ) {
            VStack(alignment: .leading, spacing: 10) {
                GenerationTierPicker(
                    tier: self.$acquisitionTier,
                    normalPrice: self.pricing.normal,
                    hardPrice: self.pricing.hard,
                    isEnabled: self.submissionState.isSubmitting == false
                )
                Text(NSLocalizedString(
                    self.acquisitionTier == .hard ? "video_preflight_tier_hard_footer" : "generation_input_tier_normal_footer",
                    comment: ""
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if self.acquisitionTier == .hard, result.reason == .antiBotChallenge {
                    Text(NSLocalizedString("video_preflight_tier_hard_antibot_hint", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(CatalogPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 主控件

    private var trimmedSiteURL: String {
        return self.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStartAssessment: Bool {
        return self.trimmedSiteURL.isEmpty == false && self.isChecking == false
    }

    /// 任何时候只有一个主控件：检查网站 / 取消检查 / 再检查一次 / 滑动生成；没有下一步的状态不显示。
    @ViewBuilder
    private var primaryControl: some View {
        if self.isChecking {
            self.capsuleButton(
                titleKey: "video_preflight_cancel_button",
                isProminent: false,
                action: self.cancelAssessment
            )
        } else if let result: VideoGenerationInputPreflight = self.result {
            if result.canSubmit {
                self.submissionControl(result)
            } else if result.status == .inconclusive {
                self.capsuleButton(
                    titleKey: "generation_input_recheck_button",
                    isProminent: true,
                    action: self.startAssessment
                )
            }
        } else {
            self.capsuleButton(
                titleKey: "video_preflight_check_button",
                isProminent: true,
                isEnabled: self.canStartAssessment,
                action: self.startAssessment
            )
        }
    }

    /// 中文注释：任务客户端未接线时保持不可用（`BC-PREFLIGHT-048`）；接线后 `canSubmit` 才可提交
    /// （accepted，或 `BC-PREFLIGHT-063` 的反爬提示放行）。只有扣 coin 的动作要滑。
    @ViewBuilder
    private func submissionControl(_ result: VideoGenerationInputPreflight) -> some View {
        let tone: SlideToConfirmControl.Tone = self.acquisitionTier == .hard ? .spectrum : .action
        if self.viewModel.canSubmitVideoGenerationTasks == false {
            SlideToConfirmControl(
                title: NSLocalizedString("video_preflight_generate_button", comment: ""),
                busyTitle: NSLocalizedString("generation_input_submitting", comment: ""),
                tone: tone,
                isEnabled: false,
                onConfirm: {}
            )
            Text(NSLocalizedString("video_preflight_transport_unavailable", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 8)
        } else {
            switch self.submissionState {
            case .idle, .submitting:
                SlideToConfirmControl(
                    title: String(format: NSLocalizedString("generation_input_slide_generate", comment: ""), self.selectedPrice),
                    busyTitle: NSLocalizedString("generation_input_submitting", comment: ""),
                    tone: tone,
                    isBusy: self.submissionState.isSubmitting,
                    onConfirm: {
                        self.startSubmission(result)
                    }
                )
            case .finished(.reused):
                SlideToConfirmControl(
                    title: String(format: NSLocalizedString("generation_input_slide_regenerate", comment: ""), self.selectedPrice),
                    busyTitle: NSLocalizedString("generation_input_submitting", comment: ""),
                    tone: tone,
                    onConfirm: {
                        self.startSubmission(result, refresh: true)
                    }
                )
            case .finished(.failed):
                SlideToConfirmControl(
                    title: String(format: NSLocalizedString("generation_input_slide_retry", comment: ""), self.selectedPrice),
                    busyTitle: NSLocalizedString("generation_input_submitting", comment: ""),
                    tone: tone,
                    onConfirm: {
                        self.startSubmission(result)
                    }
                )
            case .finished:
                EmptyView()
            }
        }
    }

    private func capsuleButton(
        titleKey: String,
        isProminent: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(NSLocalizedString(titleKey, comment: ""))
                .font(.body.weight(.semibold))
                .foregroundStyle(isProminent ? CatalogPalette.onAction : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isProminent ? CatalogPalette.addAction : CatalogPalette.fillBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.45)
    }

    // MARK: - 检查

    private func startAssessment() {
        let input: String = self.trimmedSiteURL
        guard input.isEmpty == false, self.isChecking == false else {
            return
        }
        self.assessmentTask?.cancel()
        self.cancelPendingReturn()
        self.result = nil
        self.errorMessage = nil
        self.isChecking = true
        let assessmentID: UUID = UUID()
        self.assessmentID = assessmentID
        self.assessmentTask = Task { @MainActor in
            do {
                let result: VideoGenerationInputPreflight = try await self.viewModel
                    .assessVideoGenerationInput(siteURLString: input, sourceKind: self.sourceKind)
                guard Task.isCancelled == false, self.assessmentID == assessmentID else {
                    return
                }
                self.result = result
                self.isChecking = false
                self.assessmentTask = nil
                self.assessmentID = nil
            } catch is CancellationError {
                guard self.assessmentID == assessmentID else {
                    return
                }
                self.isChecking = false
                self.assessmentTask = nil
                self.assessmentID = nil
            } catch {
                guard Task.isCancelled == false, self.assessmentID == assessmentID else {
                    return
                }
                self.errorMessage = self.message(for: error)
                self.isChecking = false
                self.assessmentTask = nil
                self.assessmentID = nil
            }
        }
    }

    private func cancelAssessment() {
        self.assessmentTask?.cancel()
        self.assessmentTask = nil
        self.assessmentID = nil
        self.isChecking = false
    }

    // MARK: - 提交

    /// 中文注释：只有 accepted 结果能走到这里；提交串由用例从 `submissionString` 取（`BC-PREFLIGHT-047`）。
    private func startSubmission(
        _ preflight: VideoGenerationInputPreflight,
        refresh: Bool = false
    ) {
        guard preflight.canSubmit, self.submissionState.isSubmitting == false else {
            return
        }
        self.submissionTask?.cancel()
        self.submissionState = .submitting
        self.submissionTask = Task { @MainActor in
            do {
                let outcome: VideoGenerationTaskSubmissionOutcome = try await self.viewModel
                    .submitVideoGenerationTask(
                        preflight: preflight,
                        sourceKind: self.sourceKind,
                        refresh: refresh,
                        acquisitionTier: self.acquisitionTier
                    )
                guard Task.isCancelled == false else {
                    return
                }
                // 中文注释：服务端复用的规则（`.reused`）只在这一屏提示「规则已存在」，不再自动添加成来源——
                // 自动添加会顺带选中它并跳到库（2026-10-03 用户裁定不要）；规则已在目录「我的生成」里，由用户自己添加。
                self.submissionState = .finished(outcome)
                if case .submitted = outcome {
                    self.scheduleReturnToSources()
                }
            } catch is CancellationError {
                self.submissionState = .idle
            } catch {
                guard Task.isCancelled == false else {
                    return
                }
                self.submissionState = .finished(.failed(code: "local-rejection"))
            }
            self.submissionTask = nil
        }
    }

    private func cancelSubmission() {
        self.submissionTask?.cancel()
        self.submissionTask = nil
        self.cancelPendingReturn()
        self.submissionState = .idle
    }

    /// 中文注释：自动返回那 1.2 秒里这一屏仍然可点，用户的任何新动作都优先——
    /// 重新检查、改 URL、自己关掉，都先撤掉待返回，免得定时器晚一步把用户刚起的新动作
    /// （比如正在跑的下一次预检）连窗口一起关掉。
    private func cancelPendingReturn() {
        self.returnTask?.cancel()
        self.returnTask = nil
    }

    /// 中文注释：只有 `.submitted` 走自动返回——那一条是「生成请求成功」的唯一形态。
    /// `.reused` 命中的是服务端已有的规则，那一屏还挂着「重新生成」入口，自动退出会把它吞掉。
    private func scheduleReturnToSources() {
        self.cancelPendingReturn()
        self.returnTask = Task { @MainActor in
            try? await Task.sleep(for: Self.submittedReturnDelay)
            guard Task.isCancelled == false else {
                return
            }
            self.returnTask = nil
            self.onFinished()
        }
    }

    // MARK: - 错误文案

    private func message(for error: Error) -> String {
        if let validationError: VideoGenerationInputURLValidationError =
            error as? VideoGenerationInputURLValidationError {
            switch validationError {
            case .empty, .invalidURL, .missingHost:
                return NSLocalizedString("video_preflight_error_invalid_url", comment: "")
            case .unsupportedScheme:
                return NSLocalizedString("video_preflight_error_scheme", comment: "")
            case .userInfoNotAllowed:
                return NSLocalizedString("video_preflight_error_unsafe_url", comment: "")
            }
        }
        if let executionIssue: VideoGenerationInputPreflightExecutionIssue =
            error as? VideoGenerationInputPreflightExecutionIssue {
            switch executionIssue {
            case .unsafeURL:
                return NSLocalizedString("video_preflight_error_unsafe_url", comment: "")
            case .unsupportedContent:
                return NSLocalizedString(
                    "video_preflight_error_unsupported_content",
                    comment: ""
                )
            case .requestFailed, .cancelled:
                break
            }
        }
        if let acquisitionError: PreflightPageAcquisitionError =
            error as? PreflightPageAcquisitionError,
            case let .rejectedStatus(statusCode) = acquisitionError {
            return NSLocalizedString(
                Self.messageKey(forRejectedStatus: statusCode),
                comment: ""
            )
        }
        return NSLocalizedString("video_preflight_error_request", comment: "")
    }

    /// `BC-PREFLIGHT-062`：站点按状态码拒绝时，文案按状态码族分。
    ///
    /// 中文注释：只分**用户的下一步不同**的那几档。404 落到「稍后重试」兜底是错的
    /// 两处——它不是暂时的，重试多少次都一样；「稍后重试」还把用户引向没用的动作，
    /// 该做的是检查网址。状态码是站点自己给的事实，这里不按 host 或路径分支
    /// （`BC-PREFLIGHT-040` / `BC-PREFLIGHT-043`）。
    private static func messageKey(forRejectedStatus statusCode: Int) -> String {
        switch statusCode {
        case 404, 410:
            return "video_preflight_error_not_found"
        case 401, 403:
            return "video_preflight_error_forbidden"
        case 429:
            return "video_preflight_error_rate_limited"
        case 500..<600:
            return "video_preflight_error_site_error"
        default:
            return "video_preflight_error_request"
        }
    }
}

enum VideoGenerationTaskSubmissionState: Equatable {
    case idle
    case submitting
    case finished(VideoGenerationTaskSubmissionOutcome)

    var isSubmitting: Bool {
        if case .submitting = self {
            return true
        }
        return false
    }
}

private extension VideoGenerationInputPreflightReason {
    var localizedDescription: String {
        switch self {
        case .multipleIndependentListFamilies:
            return NSLocalizedString("video_preflight_reason_multiple_families", comment: "")
        case .noExecutableListFamily:
            return NSLocalizedString("video_preflight_reason_no_family", comment: "")
        case .requiredCapabilityUnsupported:
            return NSLocalizedString("video_preflight_reason_capability", comment: "")
        case .entryShapeAmbiguous:
            return NSLocalizedString("video_preflight_reason_insufficient", comment: "")
        case .requiresUserSession:
            return NSLocalizedString("video_preflight_reason_session", comment: "")
        case .antiBotChallenge:
            return NSLocalizedString("video_preflight_reason_antibot", comment: "")
        case .budgetExhausted:
            return NSLocalizedString("video_preflight_reason_budget", comment: "")
        case .preflightIsolationUnavailable:
            return NSLocalizedString("video_preflight_reason_isolation", comment: "")
        }
    }
}

extension VideoGenerationInputView {
    /// 中文注释：指出是哪一个任务还没生成完——有入口 URL 就显示它的主机名，没有就用泛化文案。
    static func previousJobActiveMessage(entryURL: String?) -> String {
        guard let entryURL: String,
              entryURL.isEmpty == false else {
            return NSLocalizedString("video_preflight_submit_previous_job_active_generic", comment: "")
        }
        let display: String = URL(string: entryURL)?.host ?? entryURL
        return String(
            format: NSLocalizedString("video_preflight_submit_previous_job_active", comment: ""),
            display
        )
    }
}
