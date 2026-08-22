import Foundation
import XCTest
@testable import BrowseCraft

final class PublicURLPolicyTests: XCTestCase {
    func testPrivateLiteralAndLocalHostAreRejectedWithoutNetworkAcquisition() throws {
        let policy: PublicURLPolicy = PublicURLPolicy()
        let rejectedURLs: [String] = [
            "http://10.0.0.1/",
            "http://100.64.0.1/",
            "http://127.0.0.1/",
            "http://169.254.1.1/",
            "http://172.16.0.1/",
            "http://192.168.1.10/",
            "http://[::1]/",
            "http://[fc00::1]/",
            "http://[fe80::1]/",
            "http://[::ffff:127.0.0.1]/",
            "http://[64:ff9b::7f00:1]/",
            "http://localhost/"
        ]

        for value: String in rejectedURLs {
            XCTAssertThrowsError(
                try policy.validate(try XCTUnwrap(URL(string: value))),
                "Expected \(value) to be rejected."
            )
        }
    }

    func testPublicLiteralAndSameSiteSubdomainAreAllowed() throws {
        let policy: PublicURLPolicy = PublicURLPolicy()
        let input: URL = try XCTUnwrap(URL(string: "https://93.184.216.34/list"))

        XCTAssertNoThrow(try policy.validate(input))
        XCTAssertTrue(
            policy.isSameSite(
                try XCTUnwrap(URL(string: "https://media.example.com/list")),
                as: try XCTUnwrap(URL(string: "https://example.com/"))
            )
        )
        XCTAssertFalse(
            policy.isSameSite(
                try XCTUnwrap(URL(string: "https://notexample.com/list")),
                as: try XCTUnwrap(URL(string: "https://example.com/"))
            )
        )
    }
}
