import Foundation
import XCTest
import BrowseCraftCore
@testable import BrowseCraft

final class VideoGenerationOneHopPlannerTests: XCTestCase {
    func testPlannerCapsPrimaryAndBackupRepresentativesAtFivePlusTwo() {
        let groups: [SourceListStructuralGroup] = (1...6).map { groupIndex in
            let ownerID: String = "owner-\(groupIndex)"
            let members: [SourceListStructuralMember] = (1...3).map { memberIndex in
                SourceListStructuralMember(
                    id: "member-\(groupIndex)-\(memberIndex)",
                    ownerID: ownerID,
                    title: "List \(groupIndex)-\(memberIndex)",
                    targetURL: URL(
                        string: "https://example.com/list/\(groupIndex)/\(memberIndex)"
                    ),
                    structuralFingerprint: "member-shape",
                    positionBucket: memberIndex,
                    hasImage: false,
                    linkCount: 1
                )
            }
            return SourceListStructuralGroup(
                id: "group-\(groupIndex)",
                ownerID: ownerID,
                region: .content,
                ownerFingerprint: "owner-shape-\(groupIndex)",
                memberShapeFingerprint: "member-shape",
                familyCompatibilityFingerprint: "family-shape",
                repeatedItemOwner: true,
                titleDetailLinkCommonOwner: true,
                directLogicalChild: true,
                canOwnPublicationItems: false,
                canOwnCollectionChildren: true,
                members: members
            )
        }
        let observation: SourceListStructureObservation = self.observation(groups: groups)
        let decisions: [VideoGenerationOneHopURLDecision] = groups.flatMap { group in
            group.members.map { member in
                VideoGenerationOneHopURLDecision(
                    ownerID: group.ownerID,
                    memberID: member.id,
                    url: member.targetURL!,
                    isPublic: true,
                    isSameSite: true
                )
            }
        }

        let plan: VideoGenerationOneHopPlan = VideoGenerationOneHopPlanner().plan(
            observation: observation,
            decisions: decisions
        )

        XCTAssertEqual(plan.observedGroupCount, 6)
        XCTAssertEqual(plan.primary.count, 5)
        XCTAssertEqual(plan.backups.count, 2)
        XCTAssertEqual(Set(plan.primary.map(\.structuralGroupID)).count, 5)
        XCTAssertTrue(
            Set(plan.backups.map(\.structuralGroupID))
                .isSubset(of: Set(plan.primary.map(\.structuralGroupID)))
        )
    }

    func testPlannerUsesOnlyApprovedDirectLogicalChildren() {
        let members: [SourceListStructuralMember] = (1...3).map { index in
            SourceListStructuralMember(
                id: "member-\(index)",
                ownerID: "owner",
                title: "List \(index)",
                targetURL: URL(string: "https://example.com/list/\(index)"),
                structuralFingerprint: "member-shape",
                hasImage: false,
                linkCount: 1
            )
        }
        let observation: SourceListStructureObservation = SourceListStructureObservation(
            documentIdentity: "input",
            acquisitionIdentity: "http",
            finalURL: URL(string: "https://example.com/")!,
            purpose: .exactInput,
            lineage: nil,
            documentShape: SourceListDocumentShape(
                kind: .collectionIndexCandidate,
                fingerprint: "shape",
                repeatedOwnerCount: 1,
                contentLinkCount: 3,
                textLengthBucket: 2
            ),
            groups: [
                SourceListStructuralGroup(
                    id: "group",
                    ownerID: "owner",
                    region: .content,
                    ownerFingerprint: "owner-shape",
                    memberShapeFingerprint: "member-shape",
                    familyCompatibilityFingerprint: "family-shape",
                    repeatedItemOwner: true,
                    titleDetailLinkCommonOwner: true,
                    directLogicalChild: true,
                    canOwnPublicationItems: false,
                    canOwnCollectionChildren: true,
                    members: members
                )
            ],
            issues: []
        )
        let decisions: [VideoGenerationOneHopURLDecision] = members.map { member in
            VideoGenerationOneHopURLDecision(
                ownerID: member.ownerID,
                memberID: member.id,
                url: member.targetURL!,
                isPublic: member.id != "member-2",
                isSameSite: true
            )
        }

        let plan: VideoGenerationOneHopPlan = VideoGenerationOneHopPlanner().plan(
            observation: observation,
            decisions: decisions
        )

        XCTAssertEqual(plan.observedGroupCount, 1)
        XCTAssertEqual(plan.primary.count, 2)
        XCTAssertNotEqual(plan.primary.first?.memberID, "member-2")
        XCTAssertFalse(plan.primary.contains(where: { $0.url.host != "example.com" }))
        XCTAssertEqual(Set(plan.primary.map(\.memberID)), ["member-1", "member-3"])
    }

    private func observation(
        groups: [SourceListStructuralGroup]
    ) -> SourceListStructureObservation {
        return SourceListStructureObservation(
            documentIdentity: "input",
            acquisitionIdentity: "http",
            finalURL: URL(string: "https://example.com/")!,
            purpose: .exactInput,
            lineage: nil,
            documentShape: SourceListDocumentShape(
                kind: .collectionIndexCandidate,
                fingerprint: "shape",
                repeatedOwnerCount: groups.count,
                contentLinkCount: groups.reduce(0) { $0 + $1.members.count },
                textLengthBucket: 2
            ),
            groups: groups,
            issues: []
        )
    }
}
