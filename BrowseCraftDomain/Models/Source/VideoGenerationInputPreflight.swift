import Foundation

public enum VideoGenerationInputPreflightStatus: String, Codable, Hashable, Sendable {
    case accepted
    case rejected
    case inconclusive
}

/// `BC-PREFLIGHT` §7.1（v3）：只看入口页。
public enum VideoGenerationEntryShape: String, Codable, Hashable, Sendable {
    case directListOwner
    case multipleListFamilies
    case noListFamily
    case ambiguous
}

public enum VideoGenerationInputPreflightReason: String, Codable, Hashable, Sendable {
    case multipleIndependentListFamilies
    case noExecutableListFamily
    case requiredCapabilityUnsupported
    case entryShapeAmbiguous
    case requiresUserSession
    case antiBotChallenge
    case budgetExhausted
    case preflightIsolationUnavailable
}

public struct VideoGenerationInputPreflightAudit: Codable, Hashable, Sendable {
    public let inputAcquisitionCount: Int
    public let publicationGroupCount: Int
    public let listCount: Int
    public let familyCount: Int
    public let scanTruncated: Bool

    public init(
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

public struct VideoGenerationInputPreflight: Codable, Hashable, Sendable {
    /// `BC-PREFLIGHT-012/013`：v3 = 入口页单 family 判定（用户 2026-09-03 裁决）。
    public static let currentSchemaVersion: Int = 3
    public static let currentGeneratorPolicyVersion: String = "video-input-preflight-v3"

    public let schemaVersion: Int
    public let generatorPolicyVersion: String
    public let status: VideoGenerationInputPreflightStatus
    public let reason: VideoGenerationInputPreflightReason?
    public let evaluatedInputURL: URL
    public let submissionString: String
    public let entryShape: VideoGenerationEntryShape
    public let audit: VideoGenerationInputPreflightAudit

    public var canSubmit: Bool {
        return self.status == .accepted
    }

    public init(
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

public enum VideoGenerationInputPreflightProgress: Equatable, Sendable {
    case validatingInput
    case acquiringInput
    case observingEntryShape
    case reducingResult
}

public enum VideoGenerationInputPreflightExecutionIssue: Error, Equatable, Sendable {
    case unsafeURL
    case unsupportedContent
    case requestFailed
    case cancelled
}
