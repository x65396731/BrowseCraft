import Foundation

struct VideoGenerationInputSamplingPolicy: Hashable, Sendable {
    let maximumOneHopPrimary: Int
    let maximumOneHopBackups: Int
    let maximumDetailPrimary: Int
    let maximumDetailBackups: Int
    let maximumConcurrentRequests: Int
    let globalDeadlineSeconds: TimeInterval
    let requestTimeoutSeconds: TimeInterval

    init(
        maximumOneHopPrimary: Int = 5,
        maximumOneHopBackups: Int = 2,
        maximumDetailPrimary: Int = 5,
        maximumDetailBackups: Int = 2,
        maximumConcurrentRequests: Int = 3,
        globalDeadlineSeconds: TimeInterval = 30,
        requestTimeoutSeconds: TimeInterval = 12
    ) {
        self.maximumOneHopPrimary = maximumOneHopPrimary
        self.maximumOneHopBackups = maximumOneHopBackups
        self.maximumDetailPrimary = maximumDetailPrimary
        self.maximumDetailBackups = maximumDetailBackups
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.globalDeadlineSeconds = globalDeadlineSeconds
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }
}
