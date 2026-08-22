import Foundation
import XCTest
@testable import BrowseCraft

final class VideoGenerationInputReducerTests: XCTestCase {
    func testDirectSingleFamilyIsAccepted() throws {
        let result: VideoGenerationInputPreflight = VideoGenerationInputReducer().reduce(
            self.input(entryShape: .directListOwner, family: .oneFamilyCoversAll)
        )

        XCTAssertEqual(result.status, .accepted)
        XCTAssertTrue(result.canSubmit)
        XCTAssertNil(result.reason)
    }

    func testOneHopSingleFamilyIsAcceptedWithoutChangingInputURL() throws {
        let result: VideoGenerationInputPreflight = VideoGenerationInputReducer().reduce(
            self.input(entryShape: .oneHopListIndex, family: .oneFamilyCoversAll)
        )

        XCTAssertEqual(result.status, .accepted)
        XCTAssertEqual(result.evaluatedInputURL.absoluteString, "https://example.com/root?x=1")
        XCTAssertEqual(result.submissionString, "https://example.com/root?x=1")
    }

    func testDeeperEntryRejectsBeforeFamilyCoverage() throws {
        let result: VideoGenerationInputPreflight = VideoGenerationInputReducer().reduce(
            self.input(entryShape: .deeperDiscoveryRequired, family: .oneFamilyCoversAll)
        )

        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.reason, .inputURLRequiresDeeperDiscovery)
        XCTAssertFalse(result.canSubmit)
    }

    func testProvenDeeperEntryRejectsBeforeIncompleteAcquisitionOverlays() throws {
        let url: URL = URL(string: "https://example.com/root?x=1")!
        let result: VideoGenerationInputPreflight = VideoGenerationInputReducer().reduce(
            VideoGenerationInputReducerInput(
                inputURL: VideoGenerationInputURL(
                    evaluatedURL: url,
                    submissionString: url.absoluteString
                ),
                entryShape: .deeperDiscoveryRequired,
                familyCoverageState: .unresolved,
                acquisitionState: .antiBotChallenge,
                budgetExhausted: true,
                audit: VideoGenerationInputPreflightAudit()
            )
        )

        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.reason, .inputURLRequiresDeeperDiscovery)
    }

    func testAmbiguousEntryIsInconclusive() throws {
        let result: VideoGenerationInputPreflight = VideoGenerationInputReducer().reduce(
            self.input(entryShape: .ambiguous, family: .oneFamilyCoversAll)
        )

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.reason, .entryShapeAmbiguous)
    }

    func testFiveFamilyStatesRemainDistinct() throws {
        let cases: [(VideoGenerationFamilyCoverageState, VideoGenerationInputPreflightStatus, VideoGenerationInputPreflightReason?)] = [
            (.oneFamilyCoversAll, .accepted, nil),
            (.multipleFamiliesRequired, .rejected, .multipleIndependentListFamilies),
            (.noExecutableFamily, .rejected, .noExecutableListFamily),
            (.capabilityUnsupported, .rejected, .requiredCapabilityUnsupported),
            (.unresolved, .inconclusive, .familyIdentityUnresolved)
        ]

        for (family, status, reason) in cases {
            let result: VideoGenerationInputPreflight = VideoGenerationInputReducer().reduce(
                self.input(entryShape: .directListOwner, family: family)
            )
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(result.reason, reason)
        }
    }

    private func input(
        entryShape: VideoGenerationEntryShape,
        family: VideoGenerationFamilyCoverageState
    ) -> VideoGenerationInputReducerInput {
        let url: URL = URL(string: "https://example.com/root?x=1")!
        return VideoGenerationInputReducerInput(
            inputURL: VideoGenerationInputURL(
                evaluatedURL: url,
                submissionString: url.absoluteString
            ),
            entryShape: entryShape,
            familyCoverageState: family,
            acquisitionState: .available,
            budgetExhausted: false,
            audit: VideoGenerationInputPreflightAudit()
        )
    }
}
