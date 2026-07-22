import Foundation

/// 中文注释：只报告字段路径、问题类型及 Header/query 名称，绝不把疑似敏感值写入错误或日志。
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
        try self.validateURLLikeValue(payload.sourceID, path: "source.sourceID")
        try self.validateURLLikeValue(payload.baseURL, path: "source.baseURL")
        try self.validateConfigurationJSON(
            payload.configJSON,
            rootPath: "source.configJSON"
        )
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
        try self.validateURLLikeValue(payload.itemID, path: "favorite.itemID")
        try self.validateURLLikeValue(payload.sourceID, path: "favorite.sourceID")
        try self.validateURLLikeValue(payload.detailURL, path: "favorite.detailURL")
        if let coverURL: String = payload.coverURL {
            try self.validateURLLikeValue(coverURL, path: "favorite.coverURL")
        }
        try self.validateJSON(
            payload.itemMetadataJSON,
            rootPath: "favorite.itemMetadataJSON",
            inspectConfigurationRules: false
        )
        if let sourceSnapshotJSON: String = payload.sourceSnapshotJSON {
            try self.validateNoLocalAccountIdentity(
                sourceSnapshotJSON,
                rootPath: "favorite.sourceSnapshotJSON"
            )
            try self.validateConfigurationJSON(
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

    private func validateConfigurationJSON(_ json: String, rootPath: String) throws {
        try self.validateJSON(json, rootPath: rootPath, inspectConfigurationRules: true)
    }

    private func validateJSON(
        _ json: String,
        rootPath: String,
        inspectConfigurationRules: Bool
    ) throws {
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
        guard inspectConfigurationRules else {
            return
        }
        try self.inspect(object, path: rootPath, context: InspectionContext())
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

    private func inspect(
        _ value: Any,
        path: String,
        context: InspectionContext
    ) throws {
        if let dictionary: [String: Any] = value as? [String: Any] {
            let source: String? = dictionary["source"] as? String
            for key: String in dictionary.keys.sorted() {
                guard let child: Any = dictionary[key] else {
                    continue
                }
                let childPath: String = "\(path).\(key)"
                let normalizedKey: String = key.lowercased()

                if context.isHeaderDictionary && Self.isSensitiveHeaderName(key) {
                    throw CloudSyncPayloadSecurityError(
                        path: childPath,
                        issue: .sensitiveHeader,
                        fieldName: key
                    )
                }

                if normalizedKey == "keyhex" || normalizedKey == "ivhex" {
                    if Self.hasLiteralValue(child) {
                        throw CloudSyncPayloadSecurityError(
                            path: childPath,
                            issue: .staticKeyMaterial,
                            fieldName: key
                        )
                    }
                }

                if source?.lowercased() == "constant",
                   normalizedKey == "value",
                   Self.isClearlyPublicLiteral(child) == false {
                    throw CloudSyncPayloadSecurityError(
                        path: childPath,
                        issue: .constantSecret,
                        fieldName: nil
                    )
                }

                if context.isInsideContext,
                   Self.contextLiteralKeys.contains(normalizedKey),
                   Self.isDynamicOrEmpty(child) == false {
                    throw CloudSyncPayloadSecurityError(
                        path: childPath,
                        issue: .contextLiteral,
                        fieldName: nil
                    )
                }

                if context.isInsideRequestBody,
                   Self.isContainer(child) == false,
                   Self.isClearlyPublicLiteral(child) == false {
                    throw CloudSyncPayloadSecurityError(
                        path: childPath,
                        issue: .requestBodyLiteral,
                        fieldName: nil
                    )
                }

                let childContext: InspectionContext = InspectionContext(
                    isHeaderDictionary: normalizedKey == "headers" || normalizedKey == "imageheaders",
                    isInsideContext: context.isInsideContext || normalizedKey == "context",
                    isInsideRequestBody: context.isInsideRequestBody || normalizedKey == "body"
                )
                try self.inspect(child, path: childPath, context: childContext)
            }
            return
        }

        if let array: [Any] = value as? [Any] {
            for (index, child): (Int, Any) in array.enumerated() {
                try self.inspect(child, path: "\(path)[\(index)]", context: context)
            }
        }
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
            try self.validateURLLikeValue(string, path: path)
        }
    }

    private static let contextLiteralKeys: Set<String> = [
        "value",
        "default",
        "anonymousvalue",
        "uservalue"
    ]

    private static let publicStringLiterals: Set<String> = [
        "",
        "true",
        "false",
        "null",
        "get",
        "post",
        "put",
        "patch",
        "delete",
        "json",
        "form",
        "default",
        "server",
        "client"
    ]

    private static let sensitiveURLQueryNames: Set<String> = [
        "accesskey",
        "accesskeyid",
        "accesstoken",
        "apikey",
        "auth",
        "authorization",
        "cookie",
        "credential",
        "jwt",
        "password",
        "refreshtoken",
        "session",
        "sessionid",
        "signature",
        "signed",
        "sig",
        "token"
    ]

    private static func isSensitiveHeaderName(_ name: String) -> Bool {
        let normalized: String = name
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let exact: Set<String> = [
            "authorization",
            "proxy-authorization",
            "cookie",
            "set-cookie",
            "x-api-key",
            "x-auth-token",
            "x-device-id",
            "device-id"
        ]
        if exact.contains(normalized) {
            return true
        }
        return ["token", "secret", "password", "credential", "device", "uuid", "api-key"]
            .contains { normalized.contains($0) }
    }

    private func validateURLLikeValue(_ value: String, path: String) throws {
        if let components: URLComponents = URLComponents(string: value),
           (components.user != nil || components.password != nil) {
            throw CloudSyncPayloadSecurityError(
                path: path,
                issue: .urlUserInfo,
                fieldName: "userinfo"
            )
        }

        for queryItem: URLQueryItem in Self.queryItems(in: value) {
            guard Self.isSensitiveURLQueryName(queryItem.name),
                  let queryValue: String = queryItem.value,
                  queryValue.isEmpty == false,
                  Self.isDynamicTemplate(queryValue) == false else {
                continue
            }
            throw CloudSyncPayloadSecurityError(
                path: path,
                issue: .sensitiveURLQuery,
                fieldName: queryItem.name
            )
        }
    }

    private static func queryItems(in value: String) -> [URLQueryItem] {
        if let items: [URLQueryItem] = URLComponents(string: value)?.queryItems {
            return items
        }
        guard let queryStart: String.Index = value.firstIndex(of: "?") else {
            return []
        }
        let rawQueryStart: String.Index = value.index(after: queryStart)
        let rawQuery: Substring = value[rawQueryStart...].prefix { $0 != "#" }
        return rawQuery.split(separator: "&").map { pair in
            let parts: [Substring] = pair.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            let name: String = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value: String? = parts.count > 1
                ? String(parts[1]).removingPercentEncoding ?? String(parts[1])
                : nil
            return URLQueryItem(name: name, value: value)
        }
    }

    private static func isSensitiveURLQueryName(_ name: String) -> Bool {
        let normalized: String = name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if Self.sensitiveURLQueryNames.contains(normalized) {
            return true
        }
        return [
            "token",
            "secret",
            "signature",
            "credential",
            "password",
            "authorization",
            "cookie",
            "session",
            "apikey",
            "accesskey",
            "jwt"
        ].contains { normalized.contains($0) }
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

    private static func isClearlyPublicLiteral(_ value: Any) -> Bool {
        if value is NSNull || value is NSNumber {
            return true
        }
        guard let string: String = value as? String else {
            return false
        }
        if Self.isDynamicTemplate(string) {
            return true
        }
        if Double(string) != nil {
            return true
        }
        return Self.publicStringLiterals.contains(string.lowercased())
    }

    private static func isDynamicOrEmpty(_ value: Any) -> Bool {
        guard let string: String = value as? String else {
            return value is NSNull
        }
        return string.isEmpty || Self.isDynamicTemplate(string)
    }

    private static func isDynamicTemplate(_ string: String) -> Bool {
        return string.contains("{") && string.contains("}")
    }

    private static func hasLiteralValue(_ value: Any) -> Bool {
        if value is NSNull {
            return false
        }
        if let string: String = value as? String {
            return string.isEmpty == false
        }
        return true
    }

    private static func isContainer(_ value: Any) -> Bool {
        return value is [String: Any] || value is [Any]
    }
}

private struct InspectionContext {
    var isHeaderDictionary: Bool = false
    var isInsideContext: Bool = false
    var isInsideRequestBody: Bool = false
}
