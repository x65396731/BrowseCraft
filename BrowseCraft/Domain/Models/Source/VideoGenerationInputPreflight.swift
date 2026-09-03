import Foundation

enum VideoGenerationInputPreflightStatus: String, Codable, Hashable, Sendable {
    case accepted
    case rejected
    case inconclusive
}

/// `BC-PREFLIGHT` §7.1（v3）：只看入口页。
enum VideoGenerationEntryShape: String, Codable, Hashable, Sendable {
    case directListOwner
    case multipleListFamilies
    case noListFamily
    case ambiguous
}

enum VideoGenerationInputPreflightReason: String, Codable, Hashable, Sendable {
    case multipleIndependentListFamilies
    case noExecutableListFamily
    case requiredCapabilityUnsupported
    case entryShapeAmbiguous
    case requiresUserSession
    case antiBotChallenge
    case budgetExhausted
    case preflightIsolationUnavailable
}

struct VideoGenerationInputPreflightAudit: Codable, Hashable, Sendable {
    let inputAcquisitionCount: Int
    let publicationGroupCount: Int
    let listCount: Int
    let familyCount: Int
    let scanTruncated: Bool

    init(
        inputAcquisitionCount: Int = 1,
        publicationGroupCount: Int = 0,
        listCount: Int = 0,
        familyCount: Int = 0,
        scanTruncated: Bool = false
    ) {
        self.inputAcquisitionCount = inputAcquisitionCount
        self.publicationGroupCount = publicationGroupCount
        self.listCount = listCount
        self.familyCount = familyCount
        self.scanTruncated = scanTruncated
    }
}

struct VideoGenerationInputPreflight: Codable, Hashable, Sendable {
    /// `BC-PREFLIGHT-012/013`：v3 = 入口页单 family 判定（用户 2026-09-03 裁决）。
    static let currentSchemaVersion: Int = 3
    static let currentGeneratorPolicyVersion: String = "video-input-preflight-v3"

    let schemaVersion: Int
    let generatorPolicyVersion: String
    let status: VideoGenerationInputPreflightStatus
    let reason: VideoGenerationInputPreflightReason?
    let evaluatedInputURL: URL
    let submissionString: String
    let entryShape: VideoGenerationEntryShape
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
        self.audit = audit
    }
}

enum VideoGenerationInputPreflightProgress: Equatable, Sendable {
    case validatingInput
    case acquiringInput
    case observingEntryShape
    case reducingResult
}

enum VideoGenerationInputPreflightExecutionIssue: Error, Equatable, Sendable {
    case unsafeURL
    case unsupportedContent
    case requestFailed
    case cancelled
}
