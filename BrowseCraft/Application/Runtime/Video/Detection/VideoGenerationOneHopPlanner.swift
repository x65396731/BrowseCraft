import Foundation
import BrowseCraftCore

struct VideoGenerationOneHopURLDecision: Hashable, Sendable {
    let ownerID: String
    let memberID: String
    let url: URL
    let isPublic: Bool
    let isSameSite: Bool
}

struct VideoGenerationOneHopWorkDescriptor: Hashable, Sendable {
    let ownerID: String
    let memberID: String
    let structuralGroupID: String
    let url: URL
}

struct VideoGenerationOneHopPlan: Hashable, Sendable {
    let observedGroupCount: Int
    let primary: [VideoGenerationOneHopWorkDescriptor]
    let backups: [VideoGenerationOneHopWorkDescriptor]
}

struct VideoGenerationOneHopPlanner: Sendable {
    private let maximumPrimary: Int
    private let maximumBackups: Int

    init(maximumPrimary: Int = 5, maximumBackups: Int = 2) {
        self.maximumPrimary = maximumPrimary
        self.maximumBackups = maximumBackups
    }

    func plan(
        observation: SourceListStructureObservation,
        decisions: [VideoGenerationOneHopURLDecision]
    ) -> VideoGenerationOneHopPlan {
        let decisionByMemberID: [String: VideoGenerationOneHopURLDecision] = Dictionary(
            uniqueKeysWithValues: decisions.map { decision in
                (decision.memberID, decision)
            }
        )
        let groups: [SourceListStructuralGroup] = observation.groups.filter { group in
            group.region == .content
                && group.nestedGroupIDs.isEmpty
                && group.directLogicalChild
                && group.canOwnCollectionChildren
                && group.members.count >= 2
        }.sorted { lhs, rhs in
            if lhs.ownerFingerprint != rhs.ownerFingerprint {
                return lhs.ownerFingerprint < rhs.ownerFingerprint
            }
            return lhs.id < rhs.id
        }

        let eligibleMembersByGroupID: [String: [SourceListStructuralMember]] = Dictionary(
            uniqueKeysWithValues: groups.map { group in
                let members: [SourceListStructuralMember] = group.members.filter { member in
                    guard let decision: VideoGenerationOneHopURLDecision = decisionByMemberID[member.id] else {
                        return false
                    }
                    return decision.ownerID == group.ownerID
                        && decision.isPublic
                        && decision.isSameSite
                        && member.targetURL == decision.url
                }.sorted { lhs, rhs in
                    if lhs.positionBucket != rhs.positionBucket {
                        return lhs.positionBucket < rhs.positionBucket
                    }
                    return lhs.id < rhs.id
                }
                return (group.id, members)
            }
        )

        var primary: [VideoGenerationOneHopWorkDescriptor] = []
        var selectedMemberIDs: Set<String> = []

        // First close as many independent groups as the global budget permits.
        for group: SourceListStructuralGroup in groups {
            let eligibleMembers: [SourceListStructuralMember] = eligibleMembersByGroupID[group.id] ?? []
            guard let first: SourceListStructuralMember = eligibleMembers.first,
                  let firstURL: URL = first.targetURL else {
                continue
            }
            if primary.count < self.maximumPrimary {
                primary.append(
                    VideoGenerationOneHopWorkDescriptor(
                        ownerID: group.ownerID,
                        memberID: first.id,
                        structuralGroupID: group.id,
                        url: firstURL
                    )
                )
                selectedMemberIDs.insert(first.id)
            }
        }

        // Use remaining primary capacity to detect conflicting representatives
        // within multi-member groups before treating a shape as equivalent.
        for group: SourceListStructuralGroup in groups where primary.count < self.maximumPrimary {
            let eligibleMembers: [SourceListStructuralMember] = eligibleMembersByGroupID[group.id] ?? []
            let selectedBucket: Int? = eligibleMembers.first(where: { member in
                selectedMemberIDs.contains(member.id)
            })?.positionBucket
            let unselectedMembers: [SourceListStructuralMember] = eligibleMembers.filter { member in
                selectedMemberIDs.contains(member.id) == false
            }
            let second: SourceListStructuralMember? = unselectedMembers.first(where: { member in
                member.positionBucket != selectedBucket
            }) ?? unselectedMembers.first
            guard let second: SourceListStructuralMember = second,
                  let secondURL: URL = second.targetURL else {
                continue
            }
            primary.append(
                VideoGenerationOneHopWorkDescriptor(
                    ownerID: group.ownerID,
                    memberID: second.id,
                    structuralGroupID: group.id,
                    url: secondURL
                )
            )
            selectedMemberIDs.insert(second.id)
        }

        var backups: [VideoGenerationOneHopWorkDescriptor] = []
        let representedGroupIDs: Set<String> = Set(primary.map(\.structuralGroupID))
        for group: SourceListStructuralGroup in groups
        where representedGroupIDs.contains(group.id) && backups.count < self.maximumBackups {
            let eligibleMembers: [SourceListStructuralMember] = eligibleMembersByGroupID[group.id] ?? []
            guard let backup: SourceListStructuralMember = eligibleMembers.last(where: { member in
                selectedMemberIDs.contains(member.id) == false
            }), let backupURL: URL = backup.targetURL else {
                continue
            }
            backups.append(
                VideoGenerationOneHopWorkDescriptor(
                    ownerID: group.ownerID,
                    memberID: backup.id,
                    structuralGroupID: group.id,
                    url: backupURL
                )
            )
        }

        return VideoGenerationOneHopPlan(
            observedGroupCount: groups.count,
            primary: primary,
            backups: backups
        )
    }
}
