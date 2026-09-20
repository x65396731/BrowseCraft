import BrowseCraftDomain
import Foundation
import SwiftUI

struct VideoGenerationInputView: View {
    @Bindable var viewModel: SourcesViewModel
    /// 中文注释：预检是中性的，两种 kind 走同一套输入与判定；`sourceKind` 只决定
    /// 标题文案与提交给服务端的生成链。
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
    @State private var submissionState: VideoGenerationTaskSubmissionState = .idle
    @State private var submissionTask: Task<Void, Never>?
    @State private var reusedRuleImportFailed: Bool = false
    @State private var returnTask: Task<Void, Never>?

    /// 中文注释：提交成功后停留这么久再回来源页——让「生成任务已提交」这句确认被看见，
    /// 又不必让用户自己点两层关闭。
    private static let submittedReturnDelay: Duration = .milliseconds(1200)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        NSLocalizedString("video_preflight_url_placeholder", comment: ""),
                        text: self.$siteURL
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .disabled(self.isChecking)
                    .onSubmit {
                        self.startAssessment()
                    }
                } header: {
                    Text(NSLocalizedString("video_preflight_website_title", comment: ""))
                } footer: {
                    Text(NSLocalizedString("video_preflight_scope_footer", comment: ""))
                }

                Section {
                    Button {
                        self.startAssessment()
                    } label: {
                        HStack {
                            if self.isChecking {
                                ProgressView()
                            }
                            Text(
                                NSLocalizedString(
                                    self.isChecking
                                        ? "video_preflight_checking_button"
                                        : "video_preflight_check_button",
                                    comment: ""
                                )
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(self.canStartAssessment == false)
                    .listRowSeparatorAlignedToRowLeading()

                    if self.isChecking {
                        Button(
                            NSLocalizedString("video_preflight_cancel_button", comment: ""),
                            role: .cancel
                        ) {
                            self.cancelAssessment()
                        }
                    }
                }

                if self.isChecking {
                    self.progressSection
                }
                if let result: VideoGenerationInputPreflight = self.result {
                    VideoGenerationInputOutcomeView(
                        result: result,
                        submissionState: self.submissionState,
                        reusedRuleImportFailed: self.reusedRuleImportFailed,
                        canSubmit: self.viewModel.canSubmitVideoGenerationTasks,
                        retry: {
                            self.startAssessment()
                        },
                        submit: {
                            self.startSubmission(result)
                        },
                        regenerate: {
                            self.startSubmission(result, refresh: true)
                        }
                    )
                }
                if let errorMessage: String = self.errorMessage {
                    Section(NSLocalizedString("video_preflight_status_title", comment: "")) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .listRowSeparatorAlignedToRowLeading()
                        Button(NSLocalizedString("video_preflight_retry_button", comment: "")) {
                            self.startAssessment()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString(self.navigationTitleKey, comment: ""))
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
        }
    }

    private var navigationTitleKey: String {
        switch self.sourceKind {
        case .video:
            return "video_preflight_navigation_title"
        case .comic:
            return "comic_preflight_navigation_title"
        case .book:
            return "book_preflight_navigation_title"
        }
    }

    private var trimmedSiteURL: String {
        return self.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStartAssessment: Bool {
        return self.trimmedSiteURL.isEmpty == false && self.isChecking == false
    }

    @ViewBuilder
    private var progressSection: some View {
        Section(NSLocalizedString("video_preflight_progress_title", comment: "")) {
            Label(self.progressText, systemImage: "waveform.path.ecg")
                .foregroundStyle(.secondary)
                .listRowSeparatorAlignedToRowLeading()
        }
    }

    private var progressText: String {
        guard let progress: VideoGenerationInputPreflightProgress = self.viewModel
            .videoGenerationInputProgress else {
            return NSLocalizedString("video_preflight_progress_validating", comment: "")
        }
        switch progress {
        case .validatingInput:
            return NSLocalizedString("video_preflight_progress_validating", comment: "")
        case .acquiringInput:
            return NSLocalizedString("video_preflight_progress_acquiring", comment: "")
        case .observingEntryShape:
            return NSLocalizedString("video_preflight_progress_observing", comment: "")
        case .reducingResult:
            return NSLocalizedString("video_preflight_progress_reducing", comment: "")
        }
    }

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
                    .assessVideoGenerationInput(siteURLString: input)
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
        self.reusedRuleImportFailed = false
        self.submissionTask = Task { @MainActor in
            do {
                let outcome: VideoGenerationTaskSubmissionOutcome = try await self.viewModel
                    .submitVideoGenerationTask(
                        preflight: preflight,
                        sourceKind: self.sourceKind,
                        refresh: refresh
                    )
                guard Task.isCancelled == false else {
                    return
                }
                // 中文注释：服务端复用的规则按 Catalog 同一落地路径直接添加（`BC-PREFLIGHT-055`）。
                if case .reused(let rule) = outcome {
                    let added: Bool = await self.viewModel.addCatalogSource(rule.catalogSource)
                    guard Task.isCancelled == false else {
                        return
                    }
                    self.reusedRuleImportFailed = (added == false)
                }
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
        self.reusedRuleImportFailed = false
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

private struct VideoGenerationInputOutcomeView: View {
    let result: VideoGenerationInputPreflight
    let submissionState: VideoGenerationTaskSubmissionState
    let reusedRuleImportFailed: Bool
    let canSubmit: Bool
    let retry: () -> Void
    let submit: () -> Void
    /// 中文注释：命中服务端已生成的规则时，让用户能强制重来一次。
    /// 没有这个入口，同一入口的规则在服务端复用窗口（30 天）内无法重新生成——
    /// 站点改版或规则生成错了，用户只能干等。
    let regenerate: () -> Void

    var body: some View {
        Section(NSLocalizedString("video_preflight_status_title", comment: "")) {
            Label(self.title, systemImage: self.systemImage)
                .foregroundStyle(self.color)
                .listRowSeparatorAlignedToRowLeading()
            Text(self.detail)
                .foregroundStyle(.secondary)

            if self.result.status == .accepted {
                self.submissionRows
            } else if self.result.status == .inconclusive {
                Button(NSLocalizedString("video_preflight_retry_button", comment: "")) {
                    self.retry()
                }
            }
        }
    }

    /// 中文注释：任务客户端未接线时保持不可点（`BC-PREFLIGHT-048`）；接线后 accepted 才可提交。
    @ViewBuilder
    private var submissionRows: some View {
        if self.canSubmit == false {
            Button(NSLocalizedString("video_preflight_generate_button", comment: "")) {}
                .disabled(true)
            Text(NSLocalizedString("video_preflight_transport_unavailable", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            switch self.submissionState {
            case .idle:
                Button(NSLocalizedString("video_preflight_generate_button", comment: "")) {
                    self.submit()
                }
            case .submitting:
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("video_preflight_submitting", comment: ""))
                        .foregroundStyle(.secondary)
                }
                .listRowSeparatorAlignedToRowLeading()
            case .finished(let outcome):
                self.outcomeRows(outcome)
            }
        }
    }

    @ViewBuilder
    private func outcomeRows(_ outcome: VideoGenerationTaskSubmissionOutcome) -> some View {
        switch outcome {
        case .submitted(let receipt):
            Label(
                NSLocalizedString("video_preflight_submitted", comment: ""),
                systemImage: "paperplane.fill"
            )
            .foregroundStyle(.green)
            .listRowSeparatorAlignedToRowLeading()
            Text(
                String(
                    format: NSLocalizedString("video_preflight_submitted_job", comment: ""),
                    receipt.jobID.uuidString
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .reused(let rule):
            Label(
                NSLocalizedString("video_preflight_reused", comment: ""),
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
            .listRowSeparatorAlignedToRowLeading()
            Text(
                String(
                    format: NSLocalizedString(
                        self.reusedRuleImportFailed
                            ? "video_preflight_reused_import_failed"
                            : "video_preflight_reused_detail",
                        comment: ""
                    ),
                    rule.catalogSource.name
                )
            )
            .font(.footnote)
            .foregroundStyle(self.reusedRuleImportFailed ? .orange : .secondary)
            Button(
                NSLocalizedString("video_preflight_regenerate", comment: ""),
                action: self.regenerate
            )
            .disabled(self.submissionState.isSubmitting)
        case .authRequired:
            Label(
                NSLocalizedString("video_preflight_submit_auth_required", comment: ""),
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .foregroundStyle(.orange)
            .listRowSeparatorAlignedToRowLeading()
        case .activeJobLimit:
            Label(
                NSLocalizedString("video_preflight_submit_active_job_limit", comment: ""),
                systemImage: "hourglass"
            )
            .foregroundStyle(.orange)
            .listRowSeparatorAlignedToRowLeading()
        case .previousJobActive(let entryURL):
            Label(
                VideoGenerationInputView.previousJobActiveMessage(entryURL: entryURL),
                systemImage: "hourglass"
            )
            .foregroundStyle(.orange)
            .listRowSeparatorAlignedToRowLeading()
        case .rateLimited:
            Label(
                NSLocalizedString("video_preflight_submit_rate_limited", comment: ""),
                systemImage: "clock.badge.exclamationmark"
            )
            .foregroundStyle(.orange)
            .listRowSeparatorAlignedToRowLeading()
        case .failed(let code):
            Label(
                String(
                    format: NSLocalizedString("video_preflight_submit_failed", comment: ""),
                    code
                ),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
            .listRowSeparatorAlignedToRowLeading()
            Button(NSLocalizedString("video_preflight_generate_button", comment: "")) {
                self.submit()
            }
        }
    }

    private var title: String {
        switch self.result.status {
        case .accepted:
            return NSLocalizedString("video_preflight_outcome_accepted", comment: "")
        case .rejected:
            return NSLocalizedString("video_preflight_outcome_rejected", comment: "")
        case .inconclusive:
            return NSLocalizedString("video_preflight_outcome_inconclusive", comment: "")
        }
    }

    private var detail: String {
        guard let reason: VideoGenerationInputPreflightReason = self.result.reason else {
            return NSLocalizedString("video_preflight_reason_accepted", comment: "")
        }
        return reason.localizedDescription
    }

    private var systemImage: String {
        switch self.result.status {
        case .accepted:
            return "checkmark.circle.fill"
        case .rejected:
            return "xmark.octagon.fill"
        case .inconclusive:
            return "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch self.result.status {
        case .accepted:
            return .green
        case .rejected:
            return .red
        case .inconclusive:
            return .orange
        }
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
