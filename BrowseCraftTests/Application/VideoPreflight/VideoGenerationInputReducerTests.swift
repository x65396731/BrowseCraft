import Foundation
import XCTest
@testable import BrowseCraft
import BrowseCraftDomain
import BrowseCraftRuntime

/// `BC-PREFLIGHT` §8.1（v3）归约。
final class VideoGenerationInputReducerTests: XCTestCase {
    private func input(
        _ shape: VideoGenerationEntryShape,
        acquisition: VideoGenerationPreflightAcquisitionState = .available,
        budgetExhausted: Bool = false
    ) throws -> VideoGenerationInputReducerInput {
        let url: VideoGenerationInputURL = try VideoGenerationInputURLNormalizer().normalize("https://example.com/films/?page=2")
        return VideoGenerationInputReducerInput(
            inputURL: url,
            entryShape: shape,
            acquisitionState: acquisition,
            budgetExhausted: budgetExhausted,
            audit: VideoGenerationInputPreflightAudit(familyCount: shape == .directListOwner ? 1 : 0)
        )
    }

    func testSingleFamilyIsAcceptedWithExactInput() throws {
        let result = VideoGenerationInputReducer().reduce(try self.input(.directListOwner))
        XCTAssertEqual(result.status, .accepted)
        XCTAssertNil(result.reason)
        XCTAssertTrue(result.canSubmit)
        XCTAssertEqual(result.submissionString, "https://example.com/films/?page=2")
        XCTAssertEqual(result.schemaVersion, 3)
        XCTAssertEqual(result.generatorPolicyVersion, "video-input-preflight-v3")
    }

    func testMultipleFamiliesAreRejectedAndCannotSubmit() throws {
        let result = VideoGenerationInputReducer().reduce(try self.input(.multipleListFamilies))
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.reason, .multipleIndependentListFamilies)
        XCTAssertFalse(result.canSubmit)
    }

    func testNoListFamilyIsRejected() throws {
        let result = VideoGenerationInputReducer().reduce(try self.input(.noListFamily))
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.reason, .noExecutableListFamily)
    }

    func testAmbiguousIsInconclusive() throws {
        let result = VideoGenerationInputReducer().reduce(try self.input(.ambiguous))
        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.reason, .entryShapeAmbiguous)
    }

    func testAcquisitionStateAndDeadlinePrecedeEntryShape() throws {
        let cases: [(VideoGenerationPreflightAcquisitionState, VideoGenerationInputPreflightReason)] = [
            (.antiBotChallenge, .antiBotChallenge),
            (.requiresUserSession, .requiresUserSession),
            (.isolationUnavailable, .preflightIsolationUnavailable)
        ]
        for (state, reason) in cases {
            let result = VideoGenerationInputReducer().reduce(try self.input(.directListOwner, acquisition: state))
            XCTAssertEqual(result.status, .inconclusive)
            XCTAssertEqual(result.reason, reason)
        }
        let deadline = VideoGenerationInputReducer().reduce(try self.input(.directListOwner, budgetExhausted: true))
        XCTAssertEqual(deadline.reason, .budgetExhausted)
    }
}
