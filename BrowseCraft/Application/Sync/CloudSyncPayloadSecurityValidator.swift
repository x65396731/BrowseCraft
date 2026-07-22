import Foundation

/// 中文注释：只报告 JSON path、问题类型和 Header 名称，绝不把疑似敏感值写入错误或日志。
struct CloudSyncPayloadSecurityValidator: CloudSyncPayloadSecurityValidating {
    private static let maximumJSONBytes: Int = 800_000

    func validate(_ payload: SourceCloudPayload) throws {
        try self.validateConfigurationJSON(
            payload.configJSON,
            rootPath: "source.configJSON"
        )
    }

    func validate(_ payload: FavoriteItemCloudPayload) throws {
        try self.validateJSON(
            payload.itemMetadataJSON,
            rootPath: "favorite.itemMetadataJSON",
            inspectConfigurationRules: false
        )
        if let sourceSnapshotJSON: String = payload.sourceSnapshotJSON {
            try self.validateConfigurationJSON(
                sourceSnapshotJSON,
                rootPath: "favorite.sourceSnapshotJSON"
            )
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

        guard inspectConfigurationRules else {
            return
        }
        try self.inspect(object, path: rootPath, context: InspectionContext())
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
