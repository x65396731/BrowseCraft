import Foundation
import BrowseCraftCore

struct VideoGenerationCapabilityPolicy: Sendable {
    func entryShape(from assessment: SourceListFamilyAssessment) -> VideoGenerationEntryShape {
        let facts: SourceListEntryShapeFacts = assessment.entryShapeFacts
        if facts.deeperCollectionMemberIDs.isEmpty == false {
            return .deeperDiscoveryRequired
        }
        let hasEntryBlockingFact: Bool = assessment.unresolvedFacts.contains { fact in
            switch fact.code {
            case .entryShapeAmbiguous, .oneHopMemberUnobserved,
                 .oneHopMemberConflicting, .publicationIdentityUnresolved,
                 .budgetLimited, .acquisitionFailed, .isolationUnavailable:
                return true
            case .detailCompatibilityUnobserved, .detailCompatibilityConflicting,
                 .familyIdentityUnresolved:
                return false
            }
        }
        if hasEntryBlockingFact || facts.ambiguousMemberIDs.isEmpty == false {
            return .ambiguous
        }
        if facts.directPublicationUnitIDs.isEmpty == false,
           facts.oneHopLeafPublicationUnitIDs.isEmpty {
            return .directListOwner
        }
        if facts.oneHopLeafPublicationUnitIDs.isEmpty == false,
           facts.directPublicationUnitIDs.isEmpty {
            return .oneHopListIndex
        }
        return .ambiguous
    }

    func familyCoverageState(
        from assessment: SourceListFamilyAssessment
    ) -> VideoGenerationFamilyCoverageState {
        let requiredUnits: [SourceListPublicationUnit] = assessment.requiredPublicationUnits.filter { unit in
            unit.disposition != .nonPublication
        }
        let requiredUnitIDs: Set<String> = Set(requiredUnits.map(\.id))
        let hasBlockingFact: Bool = assessment.unresolvedFacts.contains { fact in
            switch fact.code {
            case .detailCompatibilityUnobserved, .detailCompatibilityConflicting,
                 .familyIdentityUnresolved, .publicationIdentityUnresolved,
                 .oneHopMemberUnobserved, .oneHopMemberConflicting,
                 .budgetLimited, .acquisitionFailed, .isolationUnavailable,
                 .entryShapeAmbiguous:
                return true
            }
        }
        if hasBlockingFact || requiredUnits.contains(where: { $0.disposition == .unknown }) {
            return .unresolved
        }
        if requiredUnits.contains(where: { $0.disposition == .capabilityUnsupported }) {
            return .capabilityUnsupported
        }
        guard requiredUnitIDs.isEmpty == false else {
            return .noExecutableFamily
        }

        let familyCoverage: [Set<String>] = assessment.families.map { family in
            Set(family.coveredPublicationUnitIDs).intersection(requiredUnitIDs)
        }.filter { $0.isEmpty == false }
        if familyCoverage.contains(where: { coverage in coverage == requiredUnitIDs }) {
            return .oneFamilyCoversAll
        }
        let combinedCoverage: Set<String> = familyCoverage.reduce(into: Set<String>()) { result, coverage in
            result.formUnion(coverage)
        }
        if familyCoverage.count >= 2 && combinedCoverage == requiredUnitIDs {
            return .multipleFamiliesRequired
        }
        return .unresolved
    }
}
