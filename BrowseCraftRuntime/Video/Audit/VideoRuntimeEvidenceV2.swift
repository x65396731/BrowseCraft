import Foundation

// 中文注释：这些 DTO 只属于 App 显式 runtime audit，不进入 Catalog、Core 模型或持久化播放引用。
public enum VideoRuntimeEvidenceStage: String, Codable, CaseIterable, Hashable, Sendable {
    case list
    case detail
    case episode
    case playback
}

public enum VideoRuntimeEvidenceBranch: String, Codable, Hashable, Sendable {
    case dom
    case api
    case playback
}

public enum VideoRuntimeEvidenceEnvironment: String, Codable, Hashable, Sendable {
    case pythonHTTP = "python-http"
    case playwrightWebKit = "playwright-webkit"
    case iOSWebKit = "ios-wkwebview"
    case browseCraftApp = "browsecraft-app"
}

public enum VideoRuntimeEvidenceRequestRoute: String, Codable, Hashable, Sendable {
    case http
    case webKit = "webkit"
}

public enum VideoRuntimeEvidenceCredentialStatus: String, Codable, Hashable, Sendable {
    case notRequired = "not-required"
    case validated
    case notRun = "not-run"
    case failed
}

public enum VideoRuntimeEvidenceQualityStatus: String, Codable, Hashable, Sendable {
    case passed
    case notApplicable = "not-applicable"
    case failed
}

public enum VideoRuntimeEvidenceRouteSlot: String, Codable, CaseIterable, Hashable, Sendable {
    case media
    case iframe
    case fallback

    public var order: Int {
        switch self {
        case .media:
            return 0
        case .iframe:
            return 1
        case .fallback:
            return 2
        }
    }
}

public enum VideoRuntimeEvidenceExecutionMode: String, Codable, Hashable, Sendable {
    case directMedia
    case iframeResolve
    case webUI
}

public enum VideoRuntimeEvidenceMediaKind: String, Codable, Hashable, Sendable {
    case hls
    case mp4
    case unknown
}

public enum VideoRuntimeEvidenceEncryptionStatus: String, Codable, Hashable, Sendable {
    case unencrypted
    case encrypted
    case unknown
    case notApplicable = "not-applicable"
}

public enum VideoRuntimeEvidenceMediaBindingStatus: String, Codable, Hashable, Sendable {
    case unique
    case ambiguous
    case missing
}

public enum VideoRuntimeEvidenceMediaBindingMethod: String, Codable, Hashable, Sendable {
    case nativeRequest
    case declaredIframeNavigation
    case webUIPlayerSession
}

public enum VideoRuntimeEvidenceSkipReason: String, Codable, Hashable, Sendable {
    case priorRouteSelected = "prior-route-selected"
}

public enum VideoRuntimeEvidenceBlockedCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case dash
    case drm
    case privatePlayerProtocol = "private-player-protocol"
    case arbitraryJavaScript = "arbitrary-javascript"
    case encryptedMedia = "encrypted-media"
    case browserLocalMedia = "browser-local-media"
    case manualInteraction = "manual-interaction"
}

public struct VideoRuntimeLoginEvidence: Codable, Hashable, Sendable {
    public init(
        required: Bool,
        loginURLMatchedCatalog: Bool,
        cookieDomainValidated: Bool,
        credentialReferencesValidated: Bool,
        valuesRedacted: Bool
    ) {
        self.required = required
        self.loginURLMatchedCatalog = loginURLMatchedCatalog
        self.cookieDomainValidated = cookieDomainValidated
        self.credentialReferencesValidated = credentialReferencesValidated
        self.valuesRedacted = valuesRedacted
    }

    public let required: Bool
    public let loginURLMatchedCatalog: Bool
    public let cookieDomainValidated: Bool
    public let credentialReferencesValidated: Bool
    public let valuesRedacted: Bool
}

public struct VideoRuntimeMediaBindingEvidence: Codable, Hashable, Sendable {
    public let status: VideoRuntimeEvidenceMediaBindingStatus
    public let method: VideoRuntimeEvidenceMediaBindingMethod
    public let ownerFingerprint: VideoRuntimeEvidenceFingerprint?

    public init(
        status: VideoRuntimeEvidenceMediaBindingStatus,
        method: VideoRuntimeEvidenceMediaBindingMethod,
        ownerFingerprint: VideoRuntimeEvidenceFingerprint? = nil
    ) {
        self.status = status
        self.method = method
        self.ownerFingerprint = ownerFingerprint
    }
}

public struct VideoRuntimeRouteAttemptEvidence: Codable, Hashable, Sendable {
    public let routeSlot: VideoRuntimeEvidenceRouteSlot
    public let executionMode: VideoRuntimeEvidenceExecutionMode
    public let attempted: Bool
    public let passed: Bool
    public let routeFingerprint: VideoRuntimeEvidenceFingerprint
    public let skipReason: VideoRuntimeEvidenceSkipReason?
    public let resolvedMediaKind: VideoRuntimeEvidenceMediaKind?
    public let resolvedMediaFingerprint: VideoRuntimeEvidenceFingerprint?
    public let resolvedMediaBinding: VideoRuntimeMediaBindingEvidence?
    public let encryptionStatus: VideoRuntimeEvidenceEncryptionStatus?
    public let mediaResponsePassed: Bool?
    public let bytesRead: Int?
    public let contentType: String?
    public let manifestPassed: Bool?
    public let firstMediaReferencePassed: Bool?
    public let playerStarted: Bool?
    public let rejectionReason: VideoRuntimeEvidenceRejectionReason?

    public init(
        routeSlot: VideoRuntimeEvidenceRouteSlot,
        executionMode: VideoRuntimeEvidenceExecutionMode,
        attempted: Bool,
        passed: Bool,
        routeFingerprint: VideoRuntimeEvidenceFingerprint,
        skipReason: VideoRuntimeEvidenceSkipReason? = nil,
        resolvedMediaKind: VideoRuntimeEvidenceMediaKind? = nil,
        resolvedMediaFingerprint: VideoRuntimeEvidenceFingerprint? = nil,
        resolvedMediaBinding: VideoRuntimeMediaBindingEvidence? = nil,
        encryptionStatus: VideoRuntimeEvidenceEncryptionStatus? = nil,
        mediaResponsePassed: Bool? = nil,
        bytesRead: Int? = nil,
        contentType: String? = nil,
        manifestPassed: Bool? = nil,
        firstMediaReferencePassed: Bool? = nil,
        playerStarted: Bool? = nil,
        rejectionReason: VideoRuntimeEvidenceRejectionReason? = nil
    ) {
        self.routeSlot = routeSlot
        self.executionMode = executionMode
        self.attempted = attempted
        self.passed = passed
        self.routeFingerprint = routeFingerprint
        self.skipReason = skipReason
        self.resolvedMediaKind = resolvedMediaKind
        self.resolvedMediaFingerprint = resolvedMediaFingerprint
        self.resolvedMediaBinding = resolvedMediaBinding
        self.encryptionStatus = encryptionStatus
        self.mediaResponsePassed = mediaResponsePassed
        self.bytesRead = bytesRead
        self.contentType = contentType
        self.manifestPassed = manifestPassed
        self.firstMediaReferencePassed = firstMediaReferencePassed
        self.playerStarted = playerStarted
        self.rejectionReason = rejectionReason
    }
}

public struct VideoRuntimePlaybackRouteEvidence: Codable, Hashable, Sendable {
    public init(
        detailSampleFingerprint: VideoRuntimeEvidenceFingerprint,
        groupOwnerID: String,
        groupIndex: Int,
        sampleIndex: Int,
        selectedRouteSlot: VideoRuntimeEvidenceRouteSlot?,
        routeAttempts: [VideoRuntimeRouteAttemptEvidence]
    ) {
        self.detailSampleFingerprint = detailSampleFingerprint
        self.groupOwnerID = groupOwnerID
        self.groupIndex = groupIndex
        self.sampleIndex = sampleIndex
        self.selectedRouteSlot = selectedRouteSlot
        self.routeAttempts = routeAttempts
    }

    public let detailSampleFingerprint: VideoRuntimeEvidenceFingerprint
    public let groupOwnerID: String
    public let groupIndex: Int
    public let sampleIndex: Int
    public let selectedRouteSlot: VideoRuntimeEvidenceRouteSlot?
    public let routeAttempts: [VideoRuntimeRouteAttemptEvidence]
}

public struct VideoRuntimeDetailSampleAttemptEvidence: Codable, Hashable, Sendable {
    public init(
        attempt: Int,
        detailSampleFingerprint: VideoRuntimeEvidenceFingerprint,
        detailPassed: Bool,
        detailTitlePassed: Bool,
        detailReadyStatus: VideoRuntimeEvidenceQualityStatus,
        detailCoverPassed: Bool,
        episodeGroupTitleStatus: VideoRuntimeEvidenceQualityStatus,
        episodePassed: Bool,
        playbackPassed: Bool
    ) {
        self.attempt = attempt
        self.detailSampleFingerprint = detailSampleFingerprint
        self.detailPassed = detailPassed
        self.detailTitlePassed = detailTitlePassed
        self.detailReadyStatus = detailReadyStatus
        self.detailCoverPassed = detailCoverPassed
        self.episodeGroupTitleStatus = episodeGroupTitleStatus
        self.episodePassed = episodePassed
        self.playbackPassed = playbackPassed
    }

    public let attempt: Int
    public let detailSampleFingerprint: VideoRuntimeEvidenceFingerprint
    public let detailPassed: Bool
    public let detailTitlePassed: Bool
    public let detailReadyStatus: VideoRuntimeEvidenceQualityStatus
    public let detailCoverPassed: Bool
    public let episodeGroupTitleStatus: VideoRuntimeEvidenceQualityStatus
    public let episodePassed: Bool
    public let playbackPassed: Bool
}

public struct VideoRuntimeDetailSampleSelectionEvidence: Codable, Hashable, Sendable {
    public init(
        maximumAttempts: Int,
        attemptedCount: Int,
        selectedAttempt: Int,
        attempts: [VideoRuntimeDetailSampleAttemptEvidence]
    ) {
        self.maximumAttempts = maximumAttempts
        self.attemptedCount = attemptedCount
        self.selectedAttempt = selectedAttempt
        self.attempts = attempts
    }

    public let maximumAttempts: Int
    public let attemptedCount: Int
    public let selectedAttempt: Int
    public let attempts: [VideoRuntimeDetailSampleAttemptEvidence]
}

public struct VideoRuntimePlaybackEvidenceV2: Codable, Hashable, Sendable {
    public init(
        sampleSelection: VideoRuntimeDetailSampleSelectionEvidence,
        expectedGroupOwnerIDs: [String],
        routes: [VideoRuntimePlaybackRouteEvidence]
    ) {
        self.sampleSelection = sampleSelection
        self.expectedGroupOwnerIDs = expectedGroupOwnerIDs
        self.routes = routes
    }

    public let sampleSelection: VideoRuntimeDetailSampleSelectionEvidence
    public let expectedGroupOwnerIDs: [String]
    public let routes: [VideoRuntimePlaybackRouteEvidence]
}

public struct VideoRuntimeStageEvidenceV2: Codable, Hashable, Sendable {
    public let pageID: String
    public let stage: VideoRuntimeEvidenceStage
    public let branch: VideoRuntimeEvidenceBranch
    public let environment: VideoRuntimeEvidenceEnvironment
    public let runtimeEquivalent: Bool
    public let route: VideoRuntimeEvidenceRequestRoute
    public let resolvedNeedsWebView: Bool
    public let requestMatchedCatalog: Bool
    public let parserContractPassed: Bool
    public let passed: Bool
    public let coverageComplete: Bool
    public let sampleCount: Int
    public let credentialStatus: VideoRuntimeEvidenceCredentialStatus
    public let playback: VideoRuntimePlaybackEvidenceV2?

    public init(
        pageID: String,
        stage: VideoRuntimeEvidenceStage,
        branch: VideoRuntimeEvidenceBranch,
        environment: VideoRuntimeEvidenceEnvironment,
        runtimeEquivalent: Bool,
        route: VideoRuntimeEvidenceRequestRoute,
        resolvedNeedsWebView: Bool,
        requestMatchedCatalog: Bool,
        parserContractPassed: Bool,
        passed: Bool,
        coverageComplete: Bool,
        sampleCount: Int,
        credentialStatus: VideoRuntimeEvidenceCredentialStatus,
        playback: VideoRuntimePlaybackEvidenceV2? = nil
    ) {
        self.pageID = pageID
        self.stage = stage
        self.branch = branch
        self.environment = environment
        self.runtimeEquivalent = runtimeEquivalent
        self.route = route
        self.resolvedNeedsWebView = resolvedNeedsWebView
        self.requestMatchedCatalog = requestMatchedCatalog
        self.parserContractPassed = parserContractPassed
        self.passed = passed
        self.coverageComplete = coverageComplete
        self.sampleCount = sampleCount
        self.credentialStatus = credentialStatus
        self.playback = playback
    }
}

public struct VideoRuntimeEvidenceV2: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let catalogSHA256: VideoRuntimeEvidenceFingerprint
    public let stages: [VideoRuntimeStageEvidenceV2]
    public let login: VideoRuntimeLoginEvidence?
    public let blockedCapabilities: [VideoRuntimeEvidenceBlockedCapability]

    public init(
        catalogSHA256: VideoRuntimeEvidenceFingerprint,
        stages: [VideoRuntimeStageEvidenceV2],
        login: VideoRuntimeLoginEvidence? = nil,
        blockedCapabilities: [VideoRuntimeEvidenceBlockedCapability] = []
    ) {
        self.schemaVersion = 2
        self.catalogSHA256 = catalogSHA256
        self.stages = stages
        self.login = login
        self.blockedCapabilities = blockedCapabilities
    }
}
