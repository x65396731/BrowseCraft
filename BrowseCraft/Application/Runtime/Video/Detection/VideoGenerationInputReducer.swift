import BrowseCraftDomain
import Foundation

enum VideoGenerationPreflightAcquisitionState: Equatable, Sendable {
    case available
    case requiresUserSession
    case antiBotChallenge
    case isolationUnavailable
}

struct VideoGenerationInputReducerInput: Sendable {
    let inputURL: VideoGenerationInputURL
    let entryShape: VideoGenerationEntryShape
    let acquisitionState: VideoGenerationPreflightAcquisitionState
    let budgetExhausted: Bool
    let audit: VideoGenerationInputPreflightAudit
}

/// `BC-PREFLIGHT` §8.1（v3）归约顺序：可用性 → deadline → family 数三态。
struct VideoGenerationInputReducer: Sendable {
    func reduce(_ input: VideoGenerationInputReducerInput) -> VideoGenerationInputPreflight {
        if let acquisitionReason: VideoGenerationInputPreflightReason = self.reason(
            for: input.acquisitionState
        ) {
            return self.result(status: .inconclusive, reason: acquisitionReason, input: input)
        }
        if input.budgetExhausted {
            return self.result(status: .inconclusive, reason: .budgetExhausted, input: input)
        }
        switch input.entryShape {
        case .directListOwner:
            return self.result(status: .accepted, reason: nil, input: input)
        case .multipleListFamilies:
            return self.result(status: .rejected, reason: .multipleIndependentListFamilies, input: input)
        case .noListFamily:
            return self.result(status: .rejected, reason: .noExecutableListFamily, input: input)
        case .ambiguous:
            return self.result(status: .inconclusive, reason: .entryShapeAmbiguous, input: input)
        }
    }

    private func reason(
        for state: VideoGenerationPreflightAcquisitionState
    ) -> VideoGenerationInputPreflightReason? {
        switch state {
        case .available:
            return nil
        case .requiresUserSession:
            return .requiresUserSession
        case .antiBotChallenge:
            return .antiBotChallenge
        case .isolationUnavailable:
            return .preflightIsolationUnavailable
        }
    }

    private func result(
        status: VideoGenerationInputPreflightStatus,
        reason: VideoGenerationInputPreflightReason?,
        input: VideoGenerationInputReducerInput
    ) -> VideoGenerationInputPreflight {
        return VideoGenerationInputPreflight(
            status: status,
            reason: reason,
            evaluatedInputURL: input.inputURL.evaluatedURL,
            submissionString: input.inputURL.submissionString,
            entryShape: input.entryShape,
            audit: input.audit
        )
    }
}
