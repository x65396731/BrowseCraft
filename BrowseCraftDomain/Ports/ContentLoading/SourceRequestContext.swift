import Foundation

// 中文注释：SourceRequestContext.swift 描述一次站点请求的来源和用途，供登录态、受保护资源和后续解密链路复用。

public enum SourceRequestPurpose: String, Hashable, Sendable {
    case list
    case search
    case detail
    case reader
    case image
    case video
    case rss
    case protectedResource
    case catalog
    case unknown
}

public struct SourceRequestContext: Hashable, Sendable {
    public let sourceID: String?
    public let baseURL: URL?
    public let purpose: SourceRequestPurpose
    public let refererURL: URL?
    public let additionalHeaders: [String: String]
    public let contextValues: [String: String]

    public init(
        sourceID: String? = nil,
        baseURL: URL? = nil,
        purpose: SourceRequestPurpose = .unknown,
        refererURL: URL? = nil,
        additionalHeaders: [String: String] = [:],
        contextValues: [String: String] = [:]
    ) {
        self.sourceID = sourceID
        self.baseURL = baseURL
        self.purpose = purpose
        self.refererURL = refererURL
        self.additionalHeaders = additionalHeaders
        self.contextValues = contextValues
    }
}
