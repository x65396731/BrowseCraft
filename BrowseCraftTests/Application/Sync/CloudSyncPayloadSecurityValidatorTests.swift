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
