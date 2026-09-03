import BrowseCraftDomain
import Foundation

public enum VideoGenerationPreflightAcquisitionState: Equatable, Sendable {
    case available
    case requiresUserSession
    case antiBotChallenge
    case isolationUnavailable
}

public struct VideoGenerationInputReducerInput: Sendable {
    public init(
        inputURL: VideoGenerationInputURL,
        entryShape: VideoGenerationEntryShape,
        acquisitionState: VideoGenerationPreflightAcquisitionState,
        budgetExhausted: Bool,
        audit: VideoGenerationInputPreflightAudit
    ) {
        self.inputURL = inputURL
        self.entryShape = entryShape
        self.acquisitionState = acquisitionState
        self.budgetExhausted = budgetExhausted
        self.audit = audit
    }

    public let inputURL: VideoGenerationInputURL
    public let entryShape: VideoGenerationEntryShape
    public let acquisitionState: VideoGenerationPreflightAcquisitionState
    public let budgetExhausted: Bool
    public let audit: VideoGenerationInputPreflightAudit
}

/// `BC-PREFLIGHT` §8.1（v3）归约顺序：可用性 → deadline → family 数三态。
public struct VideoGenerationInputReducer: Sendable {
    public init() {}

    public func reduce(_ input: VideoGenerationInputReducerInput) -> VideoGenerationInputPreflight {
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
