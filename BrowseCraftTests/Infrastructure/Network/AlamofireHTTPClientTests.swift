import Foundation
import Testing
@testable import BrowseCraft

struct AlamofireHTTPClientTests {
    @Test func protectedResourceResponsePreviewIsRedacted() throws {
        let responseData: Data = Data(
            #"{"data":{"key":"secret-key","iv":"secret-iv","token":"secret-token"}}"#.utf8
        )
        let preview: String = AlamofireHTTPClient.debugPreview(
            from: responseData,
            url: try #require(URL(string: "https://api.example.test/book/chapter/image/1")),
            purpose: .protectedResource
        )

        #expect(preview == "redacted-protected-resource")
        #expect(preview.contains("secret-key") == false)
        #expect(preview.contains("secret-iv") == false)
        #expect(preview.contains("secret-token") == false)
    }

    @Test func catalogResponsePreviewRemainsRedacted() throws {
        let preview: String = AlamofireHTTPClient.debugPreview(
            from: Data(#"{"encryptedRule":"catalog-secret"}"#.utf8),
            url: try #require(URL(string: "https://anyportal.online/catalog/sources")),
            purpose: .catalog
        )

        #expect(preview == "redacted-catalog-api")
    }

    @Test func ordinaryResponsePreviewRemainsAvailable() throws {
        let preview: String = AlamofireHTTPClient.debugPreview(
            from: Data("ordinary response\nwith a second line".utf8),
            url: try #require(URL(string: "https://example.test/feed")),
            purpose: .rss
        )

        #expect(preview == "ordinary response with a second line")
    }
}
