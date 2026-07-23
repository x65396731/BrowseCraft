import Foundation

/// 中文注释：云同步只验证结构、容量和明确的本地身份泄漏，不推测站点规则常量是否敏感。
struct CloudSyncPayloadSecurityValidator: CloudSyncPayloadSecurityValidating {
    private static let maximumJSONBytes: Int = 800_000
    private static let maximumRecordBytes: Int = 900_000
    private static let estimatedCloudKitOverheadBytes: Int = 8_192

    func validate(_ payload: SourceCloudPayload) throws {
        try self.validateRecordSize(
            fields: [
                payload.sourceID,
                payload.name,
                payload.baseURL,
                payload.type,
                payload.kind,
                payload.configJSON
            ],
            rootPath: "source"
        )
        try self.validateNoURLUserInfo(payload.sourceID, path: "source.sourceID")
        try self.validateNoURLUserInfo(payload.baseURL, path: "source.baseURL")
        try self.validateNoLocalAccountIdentity(
            payload.configJSON,
            rootPath: "source.configJSON"
        )
        try self.validateJSON(payload.configJSON, rootPath: "source.configJSON")
    }

    func validate(_ payload: FavoriteItemCloudPayload) throws {
        try self.validateRecordSize(
            fields: [
                payload.itemID,
                payload.sourceID,
                payload.kind,
                payload.title,
                payload.detailURL,
                payload.coverURL,
                payload.latestText,
                payload.itemMetadataJSON,
                payload.sourceSnapshotJSON
            ],
            rootPath: "favorite"
        )
        try self.validateNoURLUserInfo(payload.itemID, path: "favorite.itemID")
        try self.validateNoURLUserInfo(payload.sourceID, path: "favorite.sourceID")
        try self.validateNoURLUserInfo(payload.detailURL, path: "favorite.detailURL")
        if let coverURL: String = payload.coverURL {
            try self.validateNoURLUserInfo(coverURL, path: "favorite.coverURL")
        }
        try self.validateJSON(
            payload.itemMetadataJSON,
            rootPath: "favorite.itemMetadataJSON"
        )
        if let sourceSnapshotJSON: String = payload.sourceSnapshotJSON {
            try self.validateNoLocalAccountIdentity(
                sourceSnapshotJSON,
                rootPath: "favorite.sourceSnapshotJSON"
            )
            try self.validateJSON(
                sourceSnapshotJSON,
                rootPath: "favorite.sourceSnapshotJSON"
            )
        }
    }

    private func validateRecordSize(fields: [String?], rootPath: String) throws {
        var byteCount: Int = Self.estimatedCloudKitOverheadBytes
        for field: String in fields.compactMap({ $0 }) {
            let fieldByteCount: Int = field.utf8.count
            guard fieldByteCount <= Self.maximumRecordBytes - byteCount else {
                throw CloudSyncPayloadSecurityError(
                    path: rootPath,
                    issue: .payloadTooLarge,
                    fieldName: nil
                )
            }
            byteCount += fieldByteCount
        }
    }

    private func validateJSON(_ json: String, rootPath: String) throws {
        guard json.utf8.count <= Self.maximumJSONBytes else {
            throw CloudSyncPayloadSecurityError(
                path: rootPath,
                issue: .payloadTooLarge,
                fieldName: nil
            )
        }
        guard let data: Data = json.data(using: .utf8),
              let object: Any = try? JSONSerialization.jsonObject(with: data) else {
            throw CloudSyncPayloadSecurityError(
                path: rootPath,
                issue: .invalidJSON,
                fieldName: nil
            )
        }

        try self.inspectURLValues(object, path: rootPath)
    }

    private func validateNoLocalAccountIdentity(
        _ json: String,
        rootPath: String
    ) throws {
        guard let data: Data = json.data(using: .utf8),
              let object: Any = try? JSONSerialization.jsonObject(with: data),
              let dictionary: [String: Any] = object as? [String: Any] else {
            throw CloudSyncPayloadSecurityError(
                path: rootPath,
                issue: .invalidJSON,
                fieldName: nil
            )
        }

        if let key: String = dictionary.keys.first(where: { key in
            let normalized: String = key.lowercased()
            return normalized == "userid" || normalized == "accountscope"
        }) {
            throw CloudSyncPayloadSecurityError(
                path: "\(rootPath).\(key)",
                issue: .localAccountIdentity,
                fieldName: key
            )
        }

        if let identityPath: String = Self.localAccountIdentityPath(
            in: object,
            path: rootPath
        ) {
            throw CloudSyncPayloadSecurityError(
                path: identityPath,
                issue: .localAccountIdentity,
                fieldName: nil
            )
        }
    }

    private static func localAccountIdentityPath(in value: Any, path: String) -> String? {
        if let dictionary: [String: Any] = value as? [String: Any] {
            for key: String in dictionary.keys.sorted() {
                guard let child: Any = dictionary[key],
                      let match: String = Self.localAccountIdentityPath(
                        in: child,
                        path: "\(path).\(key)"
                      ) else {
                    continue
                }
                return match
            }
            return nil
        }
        if let array: [Any] = value as? [Any] {
            for (index, child): (Int, Any) in array.enumerated() {
                if let match: String = Self.localAccountIdentityPath(
                    in: child,
                    path: "\(path)[\(index)]"
                ) {
                    return match
                }
            }
            return nil
        }
        guard let string: String = value as? String,
              string.hasPrefix("cloud:") else {
            return nil
        }
        let hash: Substring = string.dropFirst("cloud:".count)
        guard hash.count == 64,
              hash.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else {
            return nil
        }
        return path
    }

    private func inspectURLValues(_ value: Any, path: String) throws {
        if let dictionary: [String: Any] = value as? [String: Any] {
            for key: String in dictionary.keys.sorted() {
                guard let child: Any = dictionary[key] else {
                    continue
                }
                try self.inspectURLValues(child, path: "\(path).\(key)")
            }
            return
        }
        if let array: [Any] = value as? [Any] {
            for (index, child): (Int, Any) in array.enumerated() {
                try self.inspectURLValues(child, path: "\(path)[\(index)]")
            }
            return
        }
        if let string: String = value as? String,
           Self.looksLikeURLValue(string) {
            try self.validateNoURLUserInfo(string, path: path)
        }
    }

    private func validateNoURLUserInfo(_ value: String, path: String) throws {
        if let components: URLComponents = URLComponents(string: value),
           (components.user != nil || components.password != nil) {
            throw CloudSyncPayloadSecurityError(
                path: path,
                issue: .urlUserInfo,
                fieldName: "userinfo"
            )
        }
    }

    private static func looksLikeURLValue(_ value: String) -> Bool {
        if let components: URLComponents = URLComponents(string: value),
           components.scheme?.isEmpty == false,
           components.host?.isEmpty == false {
            return true
        }
        if value.hasPrefix("//") {
            return true
        }
        guard let queryStart: String.Index = value.firstIndex(of: "?") else {
            return false
        }
        return value[value.index(after: queryStart)...].contains("=")
    }
}
