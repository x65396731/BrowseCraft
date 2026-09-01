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
        // 中文注释：同一 member 可以同时属于多个结构组（嵌套/重叠组各出一条
        // 决策），memberID 不是唯一键——决策的真实粒度是（ownerID, memberID）。
        // 用 grouping 聚合后按所属组核对，不得用 uniqueKeysWithValues（会崩溃）。
        let decisionsByMemberID: [String: [VideoGenerationOneHopURLDecision]] = Dictionary(
            grouping: decisions,
            by: { decision in
                return decision.memberID
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

        // 中文注释：groups 已按 (ownerFingerprint, id) 确定性排序；若上游出现
        // 重复 group.id，保留首个而不是崩溃。
        let eligibleMembersByGroupID: [String: [SourceListStructuralMember]] = Dictionary(
            groups.map { group in
                let members: [SourceListStructuralMember] = group.members.filter { member in
                    let memberDecisions: [VideoGenerationOneHopURLDecision] =
                        decisionsByMemberID[member.id] ?? []
                    return memberDecisions.contains { decision in
                        return decision.ownerID == group.ownerID
                            && decision.isPublic
                            && decision.isSameSite
                            && member.targetURL == decision.url
                    }
                }.sorted { lhs, rhs in
                    if lhs.positionBucket != rhs.positionBucket {
                        return lhs.positionBucket < rhs.positionBucket
                    }
                    return lhs.id < rhs.id
                }
                return (group.id, members)
            },
            uniquingKeysWith: { first, _ in
                return first
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
