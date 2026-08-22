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
    let familyCoverageState: VideoGenerationFamilyCoverageState
    let acquisitionState: VideoGenerationPreflightAcquisitionState
    let budgetExhausted: Bool
    let audit: VideoGenerationInputPreflightAudit
}

struct VideoGenerationInputReducer: Sendable {
    func reduce(_ input: VideoGenerationInputReducerInput) -> VideoGenerationInputPreflight {
        if input.entryShape == .deeperDiscoveryRequired {
            return self.result(
                status: .rejected,
                reason: .inputURLRequiresDeeperDiscovery,
                input: input
            )
        }
        if let acquisitionReason: VideoGenerationInputPreflightReason = self.reason(
            for: input.acquisitionState
        ) {
            return self.result(
                status: .inconclusive,
                reason: acquisitionReason,
                input: input
            )
        }
        if input.budgetExhausted {
            return self.result(status: .inconclusive, reason: .budgetExhausted, input: input)
        }

        switch input.entryShape {
        case .ambiguous:
            return self.result(status: .inconclusive, reason: .entryShapeAmbiguous, input: input)
        case .directListOwner, .oneHopListIndex, .deeperDiscoveryRequired:
            break
        }

        switch input.familyCoverageState {
        case .oneFamilyCoversAll:
            return self.result(status: .accepted, reason: nil, input: input)
        case .multipleFamiliesRequired:
            return self.result(
                status: .rejected,
                reason: .multipleIndependentListFamilies,
                input: input
            )
        case .noExecutableFamily:
            return self.result(
                status: .rejected,
                reason: .noExecutableListFamily,
                input: input
            )
        case .capabilityUnsupported:
            return self.result(
                status: .rejected,
                reason: .requiredCapabilityUnsupported,
                input: input
            )
        case .unresolved:
            return self.result(
                status: .inconclusive,
                reason: .familyIdentityUnresolved,
                input: input
            )
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
            familyCoverageState: input.familyCoverageState,
            audit: input.audit
        )
    }
}
