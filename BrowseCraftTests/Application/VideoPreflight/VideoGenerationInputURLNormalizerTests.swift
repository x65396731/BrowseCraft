import Foundation
import XCTest
@testable import BrowseCraft

final class VideoGenerationInputURLNormalizerTests: XCTestCase {
    func testNormalizationPreservesQueryOrderDuplicatesAndPercentEncoding() throws {
        let value: VideoGenerationInputURL = try VideoGenerationInputURLNormalizer().normalize(
            "HTTPS://Example.COM/watch?b=2&a=1&a=%2Fvalue#section"
        )

        XCTAssertEqual(
            value.submissionString,
            "https://example.com/watch?b=2&a=1&a=%2Fvalue"
        )
        XCTAssertEqual(value.evaluatedURL.absoluteString, value.submissionString)
    }

    func testNormalizationRejectsUserInfo() {
        XCTAssertThrowsError(
            try VideoGenerationInputURLNormalizer().normalize(
                "https://user:password@example.com/list"
            )
        ) { error in
            XCTAssertEqual(
                error as? VideoGenerationInputURLValidationError,
                .userInfoNotAllowed
            )
        }
    }
}
