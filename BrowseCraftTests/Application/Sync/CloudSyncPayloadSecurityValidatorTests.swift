import Foundation
import Testing
@testable import BrowseCraft

struct CloudSyncPayloadSecurityValidatorTests {
    private let validator: CloudSyncPayloadSecurityValidator = CloudSyncPayloadSecurityValidator()

    @Test func rejectsSensitiveHeaderWithoutLeakingValue() throws {
        let secret: String = "Bearer top-secret-value"
        let payload: SourceCloudPayload = Self.sourcePayload(
            configJSON: """
            {"comic":{"request":{"headers":{"Authorization":"\(secret)"}}}}
            """
        )

        do {
            try self.validator.validate(payload)
            Issue.record("Expected sensitive header rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .sensitiveHeader)
            #expect(error.fieldName == "Authorization")
            #expect(error.description.contains(secret) == false)
        }
    }

    @Test func rejectsContextRequestBodyAndStaticKeyLiterals() throws {
        let cases: [(String, CloudSyncPayloadSecurityIssue)] = [
            ("{\"context\":{\"auth\":{\"value\":\"literal-secret\"}}}", .contextLiteral),
            ("{\"request\":{\"body\":{\"password\":\"literal-secret\"}}}", .requestBodyLiteral),
            ("{\"derivation\":{\"keyHex\":\"001122\"}}", .staticKeyMaterial),
            ("{\"derivation\":{\"ivHex\":\"aabbcc\"}}", .staticKeyMaterial),
            ("{\"binding\":{\"source\":\"constant\",\"value\":\"literal-secret\"}}", .constantSecret)
        ]

        for (json, expectedIssue): (String, CloudSyncPayloadSecurityIssue) in cases {
            #expect(throws: CloudSyncPayloadSecurityError.self) {
                try self.validator.validate(Self.sourcePayload(configJSON: json))
            }
            do {
                try self.validator.validate(Self.sourcePayload(configJSON: json))
            } catch let error as CloudSyncPayloadSecurityError {
                #expect(error.issue == expectedIssue)
            }
        }
    }

    @Test func allowsDynamicReferencesAndNonSensitiveHeaders() throws {
        let payload: SourceCloudPayload = Self.sourcePayload(
            configJSON: """
            {
              "request": {
                "headers": {"Accept": "application/json"},
                "body": {"page": "{page}"}
              },
              "context": {"region": {"value": "{region}"}},
              "binding": {"source": "constant", "value": "server"}
            }
            """
        )

        try self.validator.validate(payload)
    }

    @Test func favoriteUsesMetadataJSONAndValidatesSnapshotWithSameRules() throws {
        let payload: FavoriteItemCloudPayload = Self.favoritePayload(
            sourceSnapshotJSON: """
            {"configuration":{"request":{"headers":{"X-Auth-Token":"secret"}}}}
            """
        )

        #expect(throws: CloudSyncPayloadSecurityError.self) {
            try self.validator.validate(payload)
        }
        #expect(payload.itemMetadataJSON.contains("sourceSnapshot") == false)
    }

    @Test func rejectsLocalAccountIdentityInsideFavoriteSnapshotWithoutLeakingIt() throws {
        let localScope: String = "cloud:private-local-scope"
        let payload: FavoriteItemCloudPayload = Self.favoritePayload(
            sourceSnapshotJSON: """
            {"userID":"\(localScope)","configuration":{}}
            """
        )

        do {
            try self.validator.validate(payload)
            Issue.record("Expected local account identity rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .localAccountIdentity)
            #expect(error.fieldName == "userID")
            #expect(error.description.contains(localScope) == false)
        }
    }

    @Test func rejectsNestedCloudAccountScopeWithoutLeakingIt() throws {
        let localScope: String = "cloud:" + String(repeating: "a", count: 64)
        let payload: FavoriteItemCloudPayload = Self.favoritePayload(
            sourceSnapshotJSON: """
            {"configuration":{},"metadata":{"partition":"\(localScope)"}}
            """
        )

        do {
            try self.validator.validate(payload)
            Issue.record("Expected nested local account identity rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .localAccountIdentity)
            #expect(error.path == "favorite.sourceSnapshotJSON.metadata.partition")
            #expect(error.description.contains(localScope) == false)
        }
    }

    @Test func rejectsURLUserInfoAndSensitiveQueryWithoutLeakingValues() throws {
        let username: String = "private-user"
        let password: String = "private-password"
        var source: SourceCloudPayload = Self.sourcePayload(configJSON: "{}")
        source.baseURL = "https://\(username):\(password)@example.test/catalog"

        do {
            try self.validator.validate(source)
            Issue.record("Expected URL userinfo rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .urlUserInfo)
            #expect(error.path == "source.baseURL")
            #expect(error.description.contains(username) == false)
            #expect(error.description.contains(password) == false)
        }

        let signature: String = "private-signed-value"
        var favorite: FavoriteItemCloudPayload = Self.favoritePayload(sourceSnapshotJSON: nil)
        favorite.detailURL = "https://example.test/item?page=1&X-Amz-Signature=\(signature)"

        do {
            try self.validator.validate(favorite)
            Issue.record("Expected signed URL rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .sensitiveURLQuery)
            #expect(error.path == "favorite.detailURL")
            #expect(error.fieldName == "X-Amz-Signature")
            #expect(error.description.contains(signature) == false)
        }
    }

    @Test func rejectsSensitiveURLInsideBusinessIDAndNestedJSON() throws {
        var favorite: FavoriteItemCloudPayload = Self.favoritePayload(sourceSnapshotJSON: nil)
        favorite.itemID = "https://example.test/item?access_token=private-token"

        do {
            try self.validator.validate(favorite)
            Issue.record("Expected item ID URL rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .sensitiveURLQuery)
            #expect(error.path == "favorite.itemID")
            #expect(error.fieldName == "access_token")
        }

        let source: SourceCloudPayload = Self.sourcePayload(
            configJSON: """
            {"endpoint":"/api?credential=private-value"}
            """
        )
        do {
            try self.validator.validate(source)
            Issue.record("Expected nested URL rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .sensitiveURLQuery)
            #expect(error.path == "source.configJSON.endpoint")
            #expect(error.fieldName == "credential")
        }
    }

    @Test func allowsOrdinaryURLQueriesAndDynamicSecretReferences() throws {
        var favorite: FavoriteItemCloudPayload = Self.favoritePayload(sourceSnapshotJSON: nil)
        favorite.itemID = "https://example.test/item?id=42&page=2"
        favorite.detailURL = "https://example.test/item?token={credentialStore.accessToken}"
        favorite.coverURL = "https://cdn.example.test/cover.jpg?width=640&format=webp"

        try self.validator.validate(favorite)
    }

    @Test func rejectsCombinedFavoriteFieldsOverTheRecordBudget() throws {
        let firstBlob: String = String(repeating: "a", count: 450_000)
        let secondBlob: String = String(repeating: "b", count: 450_000)
        var payload: FavoriteItemCloudPayload = Self.favoritePayload(
            sourceSnapshotJSON: "{\"configuration\":{},\"blob\":\"\(secondBlob)\"}"
        )
        payload.itemMetadataJSON = "{\"blob\":\"\(firstBlob)\"}"

        do {
            try self.validator.validate(payload)
            Issue.record("Expected combined record size rejection")
        } catch let error as CloudSyncPayloadSecurityError {
            #expect(error.issue == .payloadTooLarge)
            #expect(error.path == "favorite")
        }
    }

    private static func sourcePayload(configJSON: String) -> SourceCloudPayload {
        return SourceCloudPayload(
            schemaVersion: 1,
            userID: "cloud:must-not-upload",
            sourceID: "source-1",
            name: "Source",
            baseURL: "https://example.test",
            type: "rss",
            kind: "rss",
            configJSON: configJSON,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            deletedAt: nil
        )
    }

    private static func favoritePayload(sourceSnapshotJSON: String?) -> FavoriteItemCloudPayload {
        return FavoriteItemCloudPayload(
            schemaVersion: 1,
            userID: "cloud:must-not-upload",
            itemID: "favorite-1",
            sourceID: "source-1",
            kind: FavoriteContentKind.rss.rawValue,
            title: "Favorite",
            detailURL: "https://example.test/item",
            coverURL: nil,
            latestText: nil,
            itemMetadataJSON: "{\"idCode\":\"public-id\"}",
            sourceSnapshotJSON: sourceSnapshotJSON,
            favoritedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 2),
            deletedAt: nil
        )
    }
}
