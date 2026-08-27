import Foundation

// 中文注释：这些 DTO 只属于 App 显式 runtime audit，不进入 Catalog、Core 模型或持久化播放引用。
enum VideoRuntimeEvidenceStage: String, Codable, CaseIterable, Hashable, Sendable {
    case list
    case detail
    case episode
    case playback
}

enum VideoRuntimeEvidenceBranch: String, Codable, Hashable, Sendable {
    case dom
    case api
    case playback
}

enum VideoRuntimeEvidenceEnvironment: String, Codable, Hashable, Sendable {
    case pythonHTTP = "python-http"
    case playwrightWebKit = "playwright-webkit"
    case iOSWebKit = "ios-wkwebview"
    case browseCraftApp = "browsecraft-app"
}

enum VideoRuntimeEvidenceRequestRoute: String, Codable, Hashable, Sendable {
    case http
    case webKit = "webkit"
}

enum VideoRuntimeEvidenceCredentialStatus: String, Codable, Hashable, Sendable {
    case notRequired = "not-required"
    case validated
    case notRun = "not-run"
    case failed
}

enum VideoRuntimeEvidenceQualityStatus: String, Codable, Hashable, Sendable {
    case passed
    case notApplicable = "not-applicable"
    case failed
}

enum VideoRuntimeEvidenceRouteSlot: String, Codable, CaseIterable, Hashable, Sendable {
    case media
    case iframe
    case fallback

    var order: Int {
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

enum VideoRuntimeEvidenceExecutionMode: String, Codable, Hashable, Sendable {
    case directMedia
    case iframeResolve
    case webUI
}

enum VideoRuntimeEvidenceMediaKind: String, Codable, Hashable, Sendable {
    case hls
    case mp4
    case unknown
}

enum VideoRuntimeEvidenceEncryptionStatus: String, Codable, Hashable, Sendable {
    case unencrypted
    case encrypted
    case unknown
    case notApplicable = "not-applicable"
}

enum VideoRuntimeEvidenceMediaBindingStatus: String, Codable, Hashable, Sendable {
    case unique
    case ambiguous
    case missing
}

enum VideoRuntimeEvidenceMediaBindingMethod: String, Codable, Hashable, Sendable {
    case nativeRequest
    case declaredIframeNavigation
    case webUIPlayerSession
}

enum VideoRuntimeEvidenceSkipReason: String, Codable, Hashable, Sendable {
    case priorRouteSelected = "prior-route-selected"
}

enum VideoRuntimeEvidenceBlockedCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case dash
    case drm
    case privatePlayerProtocol = "private-player-protocol"
    case arbitraryJavaScript = "arbitrary-javascript"
    case encryptedMedia = "encrypted-media"
    case browserLocalMedia = "browser-local-media"
    case manualInteraction = "manual-interaction"
}

struct VideoRuntimeLoginEvidence: Codable, Hashable, Sendable {
    let required: Bool
    let loginURLMatchedCatalog: Bool
    let cookieDomainValidated: Bool
    let credentialReferencesValidated: Bool
    let valuesRedacted: Bool
}

struct VideoRuntimeMediaBindingEvidence: Codable, Hashable, Sendable {
    let status: VideoRuntimeEvidenceMediaBindingStatus
    let method: VideoRuntimeEvidenceMediaBindingMethod
    let ownerFingerprint: VideoRuntimeEvidenceFingerprint?

    init(
        status: VideoRuntimeEvidenceMediaBindingStatus,
        method: VideoRuntimeEvidenceMediaBindingMethod,
        ownerFingerprint: VideoRuntimeEvidenceFingerprint? = nil
    ) {
        self.status = status
        self.method = method
        self.ownerFingerprint = ownerFingerprint
    }
}

struct VideoRuntimeRouteAttemptEvidence: Codable, Hashable, Sendable {
    let routeSlot: VideoRuntimeEvidenceRouteSlot
    let executionMode: VideoRuntimeEvidenceExecutionMode
    let attempted: Bool
    let passed: Bool
    let routeFingerprint: VideoRuntimeEvidenceFingerprint
    let skipReason: VideoRuntimeEvidenceSkipReason?
    let resolvedMediaKind: VideoRuntimeEvidenceMediaKind?
    let resolvedMediaFingerprint: VideoRuntimeEvidenceFingerprint?
    let resolvedMediaBinding: VideoRuntimeMediaBindingEvidence?
    let encryptionStatus: VideoRuntimeEvidenceEncryptionStatus?
    let mediaResponsePassed: Bool?
    let bytesRead: Int?
    let contentType: String?
    let manifestPassed: Bool?
    let firstMediaReferencePassed: Bool?
    let playerStarted: Bool?
    let rejectionReason: VideoRuntimeEvidenceRejectionReason?

    init(
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

struct VideoRuntimePlaybackRouteEvidence: Codable, Hashable, Sendable {
    let detailSampleFingerprint: VideoRuntimeEvidenceFingerprint
    let groupOwnerID: String
    let groupIndex: Int
    let sampleIndex: Int
    let selectedRouteSlot: VideoRuntimeEvidenceRouteSlot?
    let routeAttempts: [VideoRuntimeRouteAttemptEvidence]
}

struct VideoRuntimeDetailSampleAttemptEvidence: Codable, Hashable, Sendable {
    let attempt: Int
    let detailSampleFingerprint: VideoRuntimeEvidenceFingerprint
    let detailPassed: Bool
    let detailTitlePassed: Bool
    let detailReadyStatus: VideoRuntimeEvidenceQualityStatus
    let detailCoverPassed: Bool
    let episodeGroupTitleStatus: VideoRuntimeEvidenceQualityStatus
    let episodePassed: Bool
    let playbackPassed: Bool
}

struct VideoRuntimeDetailSampleSelectionEvidence: Codable, Hashable, Sendable {
    let maximumAttempts: Int
    let attemptedCount: Int
    let selectedAttempt: Int
    let attempts: [VideoRuntimeDetailSampleAttemptEvidence]
}

struct VideoRuntimePlaybackEvidenceV2: Codable, Hashable, Sendable {
    let sampleSelection: VideoRuntimeDetailSampleSelectionEvidence
    let expectedGroupOwnerIDs: [String]
    let routes: [VideoRuntimePlaybackRouteEvidence]
}

struct VideoRuntimeStageEvidenceV2: Codable, Hashable, Sendable {
    let pageID: String
    let stage: VideoRuntimeEvidenceStage
    let branch: VideoRuntimeEvidenceBranch
    let environment: VideoRuntimeEvidenceEnvironment
    let runtimeEquivalent: Bool
    let route: VideoRuntimeEvidenceRequestRoute
    let resolvedNeedsWebView: Bool
    let requestMatchedCatalog: Bool
    let parserContractPassed: Bool
    let passed: Bool
    let coverageComplete: Bool
    let sampleCount: Int
    let credentialStatus: VideoRuntimeEvidenceCredentialStatus
    let playback: VideoRuntimePlaybackEvidenceV2?

    init(
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

struct VideoRuntimeEvidenceV2: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let catalogSHA256: VideoRuntimeEvidenceFingerprint
    let stages: [VideoRuntimeStageEvidenceV2]
    let login: VideoRuntimeLoginEvidence?
    let blockedCapabilities: [VideoRuntimeEvidenceBlockedCapability]

    init(
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
