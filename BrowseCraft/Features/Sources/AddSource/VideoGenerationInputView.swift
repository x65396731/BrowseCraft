import Foundation
import SwiftUI

struct VideoGenerationInputView: View {
    @ObservedObject var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var siteURL: String = ""
    @State private var result: VideoGenerationInputPreflight?
    @State private var errorMessage: String?
    @State private var assessmentTask: Task<Void, Never>?
    @State private var assessmentID: UUID?
    @State private var isChecking: Bool = false
    @State private var submissionState: VideoGenerationTaskSubmissionState = .idle
    @State private var submissionTask: Task<Void, Never>?

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
                        canSubmit: self.viewModel.canSubmitVideoGenerationTasks,
                        retry: {
                            self.startAssessment()
                        },
                        submit: {
                            self.startSubmission(result)
                        }
                    )
                }
                if let errorMessage: String = self.errorMessage {
                    Section(NSLocalizedString("video_preflight_status_title", comment: "")) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button(NSLocalizedString("video_preflight_retry_button", comment: "")) {
                            self.startAssessment()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("video_preflight_navigation_title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("video_preflight_close_button", comment: "")) {
                        self.cancelAssessment()
                        self.dismiss()
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
            }
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
        case .checkingOneHop(let completed, let budget):
            return String(
                format: NSLocalizedString("video_preflight_progress_one_hop", comment: ""),
                completed,
                budget
            )
        case .samplingDetails(let completed, let budget):
            return String(
                format: NSLocalizedString("video_preflight_progress_detail", comment: ""),
                completed,
                budget
            )
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
    private func startSubmission(_ preflight: VideoGenerationInputPreflight) {
        guard preflight.canSubmit, self.submissionState.isSubmitting == false else {
            return
        }
        self.submissionTask?.cancel()
        self.submissionState = .submitting
        self.submissionTask = Task { @MainActor in
            do {
                let outcome: VideoGenerationTaskSubmissionOutcome = try await self.viewModel
                    .submitVideoGenerationTask(preflight: preflight)
                guard Task.isCancelled == false else {
                    return
                }
                self.submissionState = .finished(outcome)
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
        self.submissionState = .idle
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
        return NSLocalizedString("video_preflight_error_request", comment: "")
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
    let canSubmit: Bool
    let retry: () -> Void
    let submit: () -> Void

    var body: some View {
        Section(NSLocalizedString("video_preflight_status_title", comment: "")) {
            Label(self.title, systemImage: self.systemImage)
                .foregroundStyle(self.color)
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
            Text(
                String(
                    format: NSLocalizedString("video_preflight_submitted_job", comment: ""),
                    receipt.jobID.uuidString
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .authRequired:
            Label(
                NSLocalizedString("video_preflight_submit_auth_required", comment: ""),
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .foregroundStyle(.orange)
        case .activeJobLimit:
            Label(
                NSLocalizedString("video_preflight_submit_active_job_limit", comment: ""),
                systemImage: "hourglass"
            )
            .foregroundStyle(.orange)
        case .failed(let code):
            Label(
                String(
                    format: NSLocalizedString("video_preflight_submit_failed", comment: ""),
                    code
                ),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
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
        case .inputURLRequiresDeeperDiscovery:
            return NSLocalizedString("video_preflight_reason_deeper", comment: "")
        case .multipleIndependentListFamilies:
            return NSLocalizedString("video_preflight_reason_multiple_families", comment: "")
        case .noExecutableListFamily:
            return NSLocalizedString("video_preflight_reason_no_family", comment: "")
        case .requiredCapabilityUnsupported:
            return NSLocalizedString("video_preflight_reason_capability", comment: "")
        case .entryShapeAmbiguous, .familyIdentityUnresolved:
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
