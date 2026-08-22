import Foundation

enum VideoGenerationInputPreflightStatus: String, Codable, Hashable, Sendable {
    case accepted
    case rejected
    case inconclusive
}

enum VideoGenerationEntryShape: String, Codable, Hashable, Sendable {
    case directListOwner
    case oneHopListIndex
    case deeperDiscoveryRequired
    case ambiguous
}

enum VideoGenerationFamilyCoverageState: String, Codable, Hashable, Sendable {
    case oneFamilyCoversAll
    case multipleFamiliesRequired
    case noExecutableFamily
    case capabilityUnsupported
    case unresolved
}

enum VideoGenerationInputPreflightReason: String, Codable, Hashable, Sendable {
    case inputURLRequiresDeeperDiscovery
    case multipleIndependentListFamilies
    case noExecutableListFamily
    case requiredCapabilityUnsupported
    case entryShapeAmbiguous
    case familyIdentityUnresolved
    case requiresUserSession
    case antiBotChallenge
    case budgetExhausted
    case preflightIsolationUnavailable
}

struct VideoGenerationInputPreflightAudit: Codable, Hashable, Sendable {
    let inputAcquisitionCount: Int
    let oneHopObservedGroupCount: Int
    let oneHopAcquiredRepresentativeCount: Int
    let oneHopQualifiedLeafCount: Int
    let detailAcquiredRepresentativeCount: Int
    let unresolvedFactCount: Int

    init(
        inputAcquisitionCount: Int = 1,
        oneHopObservedGroupCount: Int = 0,
        oneHopAcquiredRepresentativeCount: Int = 0,
        oneHopQualifiedLeafCount: Int = 0,
        detailAcquiredRepresentativeCount: Int = 0,
        unresolvedFactCount: Int = 0
    ) {
        self.inputAcquisitionCount = inputAcquisitionCount
        self.oneHopObservedGroupCount = oneHopObservedGroupCount
        self.oneHopAcquiredRepresentativeCount = oneHopAcquiredRepresentativeCount
        self.oneHopQualifiedLeafCount = oneHopQualifiedLeafCount
        self.detailAcquiredRepresentativeCount = detailAcquiredRepresentativeCount
        self.unresolvedFactCount = unresolvedFactCount
    }
}

struct VideoGenerationInputPreflight: Codable, Hashable, Sendable {
    static let currentSchemaVersion: Int = 2
    static let currentGeneratorPolicyVersion: String = "video-input-preflight-v2"

    let schemaVersion: Int
    let generatorPolicyVersion: String
    let status: VideoGenerationInputPreflightStatus
    let reason: VideoGenerationInputPreflightReason?
    let evaluatedInputURL: URL
    let submissionString: String
    let entryShape: VideoGenerationEntryShape
    let familyCoverageState: VideoGenerationFamilyCoverageState
    let audit: VideoGenerationInputPreflightAudit

    var canSubmit: Bool {
        return self.status == .accepted
    }

    init(
        status: VideoGenerationInputPreflightStatus,
        reason: VideoGenerationInputPreflightReason?,
        evaluatedInputURL: URL,
        submissionString: String,
        entryShape: VideoGenerationEntryShape,
        familyCoverageState: VideoGenerationFamilyCoverageState,
        audit: VideoGenerationInputPreflightAudit
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatorPolicyVersion = Self.currentGeneratorPolicyVersion
        self.status = status
        self.reason = reason
        self.evaluatedInputURL = evaluatedInputURL
        precondition(evaluatedInputURL.absoluteString == submissionString)
        self.submissionString = submissionString
        self.entryShape = entryShape
        self.familyCoverageState = familyCoverageState
        self.audit = audit
    }
}

enum VideoGenerationInputPreflightProgress: Equatable, Sendable {
    case validatingInput
    case acquiringInput
    case observingEntryShape
    case checkingOneHop(completed: Int, budget: Int)
    case samplingDetails(completed: Int, budget: Int)
    case reducingResult
}

enum VideoGenerationInputPreflightExecutionIssue: Error, Equatable, Sendable {
    case unsafeURL
    case unsupportedContent
    case requestFailed
    case cancelled
}
