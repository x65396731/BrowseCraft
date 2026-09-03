import CryptoKit
import Foundation

public struct VideoRuntimeEvidenceFingerprint: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.utf8.count == 64,
              rawValue.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        let value: String = try container.decode(String.self)
        guard let fingerprint = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a 64-character lowercase SHA-256 value."
            )
        }
        self = fingerprint
    }

    public func encode(to encoder: any Encoder) throws {
        var container: SingleValueEncodingContainer = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    fileprivate init(digest: SHA256.Digest) {
        self.rawValue = digest.map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}

public struct VideoRuntimeEvidenceRejectionReason: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let bytes: [UInt8] = Array(rawValue.utf8)
        guard (1...64).contains(bytes.count),
              let first: UInt8 = bytes.first,
              (97...122).contains(first),
              bytes.allSatisfy({ byte in
                  (97...122).contains(byte)
                      || (48...57).contains(byte)
                      || byte == 45
              }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        let value: String = try container.decode(String.self)
        guard let reason = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a lowercase kebab-case rejection reason up to 64 bytes."
            )
        }
        self = reason
    }

    public func encode(to encoder: any Encoder) throws {
        var container: SingleValueEncodingContainer = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

public enum VideoRuntimeAuditCatalogInputError: Error, Equatable, Sendable {
    case emptyCatalog
    case invalidCatalogJSON
    case invalidCatalogRoot
}

// 中文注释：保留审计 artifact 的原始字节；catalogSHA256 绝不从解码后模型重新编码得到。
public struct VideoRuntimeAuditCatalogInput: Sendable {
    public let rawCatalogData: Data
    public let catalogSHA256: VideoRuntimeEvidenceFingerprint

    public init(rawCatalogData: Data) throws {
        guard rawCatalogData.isEmpty == false else {
            throw VideoRuntimeAuditCatalogInputError.emptyCatalog
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: rawCatalogData)
        } catch {
            throw VideoRuntimeAuditCatalogInputError.invalidCatalogJSON
        }
        guard let root: [String: Any] = value as? [String: Any],
              Set(root.keys) == Set(["id", "name", "baseURL", "kind", "ruleJSON"]),
              root["kind"] as? String == "video",
              root["ruleJSON"] is [String: Any] else {
            throw VideoRuntimeAuditCatalogInputError.invalidCatalogRoot
        }
        self.rawCatalogData = rawCatalogData
        self.catalogSHA256 = VideoRuntimeEvidenceFingerprint(
            digest: SHA256.hash(data: rawCatalogData)
        )
    }
}

public enum VideoRuntimeEvidenceFingerprintError: Error, Equatable, Sendable {
    case emptyIdentityComponent(String)
    case invalidResourceURL
    case invalidGroupIndex
}

public enum VideoRuntimeEvidenceFingerprintFactory: Sendable {
    public static func detailSample(
        catalogSHA256: VideoRuntimeEvidenceFingerprint,
        pageID: String,
        stableDetailURL: URL
    ) throws -> VideoRuntimeEvidenceFingerprint {
        return try self.fingerprint(
            namespace: "video-runtime-detail-v2",
            components: [
                ("catalog", catalogSHA256.rawValue),
                ("page", self.required(pageID, name: "pageID")),
                ("detail", self.canonicalNetworkResourceIdentity(stableDetailURL))
            ]
        )
    }

    public static func route(
        catalogSHA256: VideoRuntimeEvidenceFingerprint,
        pageID: String,
        detailSampleFingerprint: VideoRuntimeEvidenceFingerprint,
        groupOwnerID: String,
        routeSlot: VideoRuntimeEvidenceRouteSlot,
        declaredRuleBody: Data
    ) throws -> VideoRuntimeEvidenceFingerprint {
        guard declaredRuleBody.isEmpty == false else {
            throw VideoRuntimeEvidenceFingerprintError.emptyIdentityComponent(
                "declaredRuleBody"
            )
        }
        let ruleBodyDigest = VideoRuntimeEvidenceFingerprint(
            digest: SHA256.hash(data: declaredRuleBody)
        )
        return try self.fingerprint(
            namespace: "video-runtime-route-v2",
            components: [
                ("catalog", catalogSHA256.rawValue),
                ("page", self.required(pageID, name: "pageID")),
                ("detail", detailSampleFingerprint.rawValue),
                ("group", self.required(groupOwnerID, name: "groupOwnerID")),
                ("slot", routeSlot.rawValue),
                ("rule", ruleBodyDigest.rawValue)
            ]
        )
    }

    public static func owner(
        routeFingerprint: VideoRuntimeEvidenceFingerprint,
        playbackSessionID: UUID
    ) throws -> VideoRuntimeEvidenceFingerprint {
        return try self.fingerprint(
            namespace: "video-runtime-owner-v2",
            components: [
                ("route", routeFingerprint.rawValue),
                ("session", playbackSessionID.uuidString.lowercased())
            ]
        )
    }

    // 中文注释：媒体身份忽略 userinfo/query/fragment 和 host，只保留媒体种类与稳定 path。
    // 这会保守地把等价 CDN 镜像归为同一媒体，避免凭据刷新或换壳被当作独立安全 fallback。
    public static func media(
        kind: VideoRuntimeEvidenceMediaKind,
        resourceURL: URL
    ) throws -> VideoRuntimeEvidenceFingerprint {
        guard kind != .unknown else {
            throw VideoRuntimeEvidenceFingerprintError.emptyIdentityComponent("mediaKind")
        }
        return try self.fingerprint(
            namespace: "video-runtime-media-v2",
            components: [
                ("kind", kind.rawValue),
                ("resource", self.canonicalNetworkResourceIdentity(resourceURL))
            ]
        )
    }

    public static func groupOwnerID(pageID: String, groupIndex: Int) throws -> String {
        guard groupIndex > 0 else {
            throw VideoRuntimeEvidenceFingerprintError.invalidGroupIndex
        }
        return "\(try self.required(pageID, name: "pageID"))::group:\(groupIndex)"
    }

    private static func canonicalNetworkResourceIdentity(_ url: URL) throws -> String {
        guard let components: URLComponents = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        let scheme: String = components.scheme?.lowercased(),
        scheme == "http" || scheme == "https",
        components.host?.isEmpty == false else {
            throw VideoRuntimeEvidenceFingerprintError.invalidResourceURL
        }
        let path: String = components.percentEncodedPath.isEmpty
            ? "/"
            : components.percentEncodedPath
        return "network-path:\(path)"
    }

    private static func required(_ value: String, name: String) throws -> String {
        let normalized: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw VideoRuntimeEvidenceFingerprintError.emptyIdentityComponent(name)
        }
        return normalized
    }

    private static func fingerprint(
        namespace: String,
        components: [(String, String)]
    ) throws -> VideoRuntimeEvidenceFingerprint {
        var canonicalData = Data()
        self.append(namespace, to: &canonicalData)
        for (name, value) in components {
            self.append(try self.required(name, name: "componentName"), to: &canonicalData)
            self.append(try self.required(value, name: name), to: &canonicalData)
        }
        return VideoRuntimeEvidenceFingerprint(digest: SHA256.hash(data: canonicalData))
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        var length: UInt64 = UInt64(bytes.count).bigEndian
        Swift.withUnsafeBytes(of: &length) { lengthBytes in
            data.append(contentsOf: lengthBytes)
        }
        data.append(bytes)
    }
}
