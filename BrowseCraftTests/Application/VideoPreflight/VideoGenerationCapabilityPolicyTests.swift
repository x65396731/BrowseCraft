import Foundation
import XCTest
import BrowseCraftCore
@testable import BrowseCraft

final class VideoGenerationCapabilityPolicyTests: XCTestCase {
    func testOneFamilyCoveringAllRequiredUnitsIsClosed() {
        let assessment: SourceListFamilyAssessment = self.assessment(
            units: [self.unit("a"), self.unit("b")],
            families: [self.family("one", covers: ["a", "b"])]
        )

        XCTAssertEqual(
            VideoGenerationCapabilityPolicy().familyCoverageState(from: assessment),
            .oneFamilyCoversAll
        )
    }

    func testIndependentFamiliesRemainDistinct() {
        let assessment: SourceListFamilyAssessment = self.assessment(
            units: [self.unit("a"), self.unit("b")],
            families: [
                self.family("one", covers: ["a"]),
                self.family("two", covers: ["b"])
            ]
        )

        XCTAssertEqual(
            VideoGenerationCapabilityPolicy().familyCoverageState(from: assessment),
            .multipleFamiliesRequired
        )
    }

    func testCapabilityAndEvidenceGapsDoNotCollapseTogether() {
        let unsupported: SourceListFamilyAssessment = self.assessment(
            units: [self.unit("a", disposition: .capabilityUnsupported)],
            families: []
        )
        let unresolved: SourceListFamilyAssessment = self.assessment(
            units: [self.unit("a")],
            families: [],
            unresolved: [
                SourceListUnresolvedFact(
                    code: .detailCompatibilityUnobserved,
                    documentIdentity: "input"
                )
            ]
        )

        XCTAssertEqual(
            VideoGenerationCapabilityPolicy().familyCoverageState(from: unsupported),
            .capabilityUnsupported
        )
        XCTAssertEqual(
            VideoGenerationCapabilityPolicy().familyCoverageState(from: unresolved),
            .unresolved
        )
    }

    private func assessment(
        units: [SourceListPublicationUnit],
        families: [SourceListFamilyCoverage],
        unresolved: [SourceListUnresolvedFact] = []
    ) -> SourceListFamilyAssessment {
        return SourceListFamilyAssessment(
            entryShapeFacts: SourceListEntryShapeFacts(directPublicationUnitIDs: units.map(\.id)),
            requiredPublicationUnits: units,
            families: families,
            redundantObservations: [],
            unresolvedFacts: unresolved
        )
    }

    private func unit(
        _ id: String,
        disposition: SourceListMemberDisposition = .qualified
    ) -> SourceListPublicationUnit {
        return SourceListPublicationUnit(
            id: id,
            documentIdentity: "input",
            ownerID: "owner-" + id,
            disposition: disposition
        )
    }

    private func family(_ id: String, covers unitIDs: [String]) -> SourceListFamilyCoverage {
        return SourceListFamilyCoverage(
            familyID: id,
            coveredPublicationUnitIDs: unitIDs,
            supportingObservationIdentities: ["observation-" + id]
        )
    }
}
