import BrowseCraftCore
import Foundation
import XCTest
@testable import BrowseCraft

/// 归档形态验收（设计书 §13.15，开发计划 Phase 6）：用 `Resources/PreflightFixtures/<site>/manifest.json`
/// 描述的匿名文档驱动真实 use case（真实 observer / assessor / reducer），只桩掉网络。
///
/// 中文注释：fixture 只承载预期；结论不符时先在固定输入上归因，不改判据迁就样本（`BC-PREFLIGHT-043`）。
final class VideoGenerationPreflightArchiveFixtureTests: XCTestCase {
    private struct FixtureManifest: Decodable {
        struct Document: Decodable {
            let name: String
            let stage: String
            let url: String
            let file: String
        }

        struct Expected: Decodable {
            let status: String
            let entryShape: String
        }

        let fixtureID: String
        let entryURL: String
        let expected: Expected
        /// `ready` 才参与断言；`pending` 只打印报告（归档覆盖或判据归因未完成，见 `pendingReason`）。
        let acceptance: String
        let pendingReason: String
        let note: String
        let documents: [Document]
    }

    /// 只回放 manifest 里有的 URL；未归档的 URL 以 `requestFailed` 失败，让缺口以 typed 事实暴露。
    private actor ArchiveLoader: PreflightPageAcquiring {
        private let pages: [String: Data]
        private(set) var missing: [String] = []

        init(pages: [String: Data]) {
            self.pages = pages
        }

        func acquire(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
            let key: String = Self.key(request.url)
            guard let data: Data = self.pages[key] else {
                self.missing.append(request.url.absoluteString)
                throw PreflightPageAcquisitionError.rejectedStatus(404)
            }
            return PreflightAcquiredPage(
                requestedURL: request.url,
                data: data,
                finalURL: request.url,
                statusCode: 200,
                mediaType: "text/html",
                textEncodingName: "utf-8",
                acquisitionIdentity: "archive:\(key)",
                source: .http,
                isolationScope: .fullHTTP
            )
        }

        func missingURLs() -> [String] {
            return self.missing
        }

        static func key(_ url: URL) -> String {
            var string: String = url.absoluteString
            if string.hasSuffix("/") {
                string.removeLast()
            }
            return string
        }
    }

    /// 归约事实直方图（只读诊断，供 B.3 归因）。
    private final class FactsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var text: String = "-"
        private var groups: String = ""

        func record(_ input: SourceListFamilyAssessmentInput, _ assessment: SourceListFamilyAssessment) {
            var codes: [String: Int] = [:]
            for fact in assessment.unresolvedFacts {
                codes["\(fact.code)", default: 0] += 1
            }
            // 入口页每个内容组：区域 / 发布 / 集合 / 成员数 / 有图数 / 一跳与 detail 观测数 / 指向它的事实码。
            let entry = input.inputObservation
            var groupLines: [String] = []
            for group in entry.groups where group.region == .content && group.nestedGroupIDs.isEmpty {
                let oneHop = input.oneHopObservations.filter { $0.parentOwnerID == group.ownerID }.count
                let details = input.detailObservations.filter { $0.parentOwnerID == group.ownerID }.count
                let factCodes = assessment.unresolvedFacts.filter { $0.ownerID == group.ownerID && $0.documentIdentity == entry.documentIdentity }
                    .reduce(into: [String: Int]()) { $0["\($1.code)", default: 0] += 1 }
                groupLines.append("      group \(group.id.suffix(8)) pub=\(group.canOwnPublicationItems ? 1 : 0) col=\(group.canOwnCollectionChildren ? 1 : 0) n=\(group.members.count) img=\(group.members.filter(\.hasImage).count) oneHop=\(oneHop) detail=\(details) facts=\(factCodes) e.g. \(group.members.first?.targetURL?.path ?? "-")")
            }
            self.lock.lock(); self.groups = groupLines.joined(separator: "\n"); self.lock.unlock()
            let facts = assessment.entryShapeFacts
            let families = assessment.families.map { family in
                "\(family.familyID.suffix(6)):\(family.coveredPublicationUnitIDs.count)"
            }
            let dispositions = assessment.requiredPublicationUnits.reduce(into: [String: Int]()) { acc, unit in
                acc["\(unit.disposition)", default: 0] += 1
            }
            let summary: String = "direct=\(facts.directPublicationUnitIDs.count) " +
                "oneHopLeaf=\(facts.oneHopLeafPublicationUnitIDs.count) " +
                "deeper=\(facts.deeperCollectionMemberIDs.count) " +
                "ambiguousMembers=\(facts.ambiguousMemberIDs.count) " +
                "units=\(dispositions) families=\(families) codes=\(codes)"
            self.lock.lock()
            self.text = summary
            self.lock.unlock()
        }

        func summary() -> String {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.text + "\n" + self.groups
        }
    }

    private struct RenderedUnavailable: PreflightRenderedPageAcquiring {
        @MainActor
        func acquireRendered(_ request: PreflightPageRequest) async throws -> PreflightAcquiredPage {
            throw PreflightPageAcquisitionError.isolationUnavailable
        }
    }

    private struct SameHostPolicy: PublicURLChecking {
        func validate(_ url: URL) throws {}

        func isSameSite(_ candidate: URL, as inputURL: URL) -> Bool {
            return candidate.host?.lowercased() == inputURL.host?.lowercased()
        }
    }

    /// 中文注释：目录名只用 alias，真实主机名不进生产分支（开发计划 Phase 6）；
    /// alias ↔ 站点映射只存在于 fwq `scripts/export_preflight_fixtures.py`。
    /// 测量开关：`TEST_RUNNER_PREFLIGHT_DETAIL_SHAPE=lineageAware`（章程 2026-09-03 core-detail-document-shape）。
    private static var detailShapePolicy: SourceListDetailShapePolicy {
        let raw: String = ProcessInfo.processInfo.environment["PREFLIGHT_DETAIL_SHAPE"] ?? "legacy"
        return SourceListDetailShapePolicy(rawValue: raw) ?? .legacy
    }

    /// 测量开关：`TEST_RUNNER_PREFLIGHT_OVERLAP=recordOnly`（子项 1）。
    private static var overlapPolicy: SourceListOverlapPolicy {
        let raw: String = ProcessInfo.processInfo.environment["PREFLIGHT_OVERLAP"] ?? "legacy"
        return SourceListOverlapPolicy(rawValue: raw) ?? .legacy
    }

    private static var publicationOwnerPolicy: SourceListPublicationOwnerPolicy {
        SourceListPublicationOwnerPolicy(rawValue: ProcessInfo.processInfo.environment["PREFLIGHT_PUBLICATION_OWNER"] ?? "legacy") ?? .legacy
    }

    private static var chromePolicy: SourceListChromePolicy {
        SourceListChromePolicy(rawValue: ProcessInfo.processInfo.environment["PREFLIGHT_CHROME"] ?? "legacy") ?? .legacy
    }

    private static let fixtureSites: [String] = [
        "site-a", "site-b", "site-c", "site-d", "site-e", "site-f-films", "site-f-home"
    ]

    func testArchiveFixturesMatchAcceptanceMatrixRow15() async throws {
        var report: [String] = []
        var failures: [String] = []
        for site: String in Self.fixtureSites {
            let manifest: FixtureManifest = try self.loadManifest(site)
            var pages: [String: Data] = [:]
            for document in manifest.documents {
                let data: Data = try self.loadDocument(site, document.file)
                pages[ArchiveLoader.key(URL(string: document.url)!)] = data
            }
            let loader = ArchiveLoader(pages: pages)
            let factsBox = FactsBox()
            let useCase = AssessVideoGenerationInputUseCase(
                publicURLPolicy: SameHostPolicy(),
                httpLoader: loader,
                renderedLoader: RenderedUnavailable(),
                structureObserver: DefaultSourceListStructureObserver(detailShapePolicy: Self.detailShapePolicy, overlapPolicy: Self.overlapPolicy, publicationOwnerPolicy: Self.publicationOwnerPolicy),
                familyAssessor: DefaultSourceListFamilyAssessor(chromePolicy: Self.chromePolicy),
                assessmentObserver: { input, assessment in
                    factsBox.record(input, assessment)
                }
            )
            let result: VideoGenerationInputPreflight = try await useCase.execute(
                siteURLString: manifest.entryURL,
                progress: nil
            )
            let missing: [String] = await loader.missingURLs()
            let line: String = "\(site): status=\(result.status.rawValue) " +
                "entryShape=\(result.entryShape.rawValue) " +
                "coverage=\(result.familyCoverageState.rawValue) " +
                "reason=\(result.reason?.rawValue ?? "-") " +
                "oneHop=\(result.audit.oneHopObservedGroupCount)/" +
                "\(result.audit.oneHopAcquiredRepresentativeCount)/" +
                "\(result.audit.oneHopQualifiedLeafCount) " +
                "detail=\(result.audit.detailAcquiredRepresentativeCount) " +
                "unresolved=\(result.audit.unresolvedFactCount) missing=\(missing.count)"
            report.append(line)
            report.append("  facts: " + factsBox.summary())
            XCTAssertEqual(
                result.submissionString,
                manifest.entryURL,
                "\(site): accepted/rejected 都必须保持精确输入串（BC-PREFLIGHT-014）"
            )
            let matches: Bool = result.status.rawValue == manifest.expected.status
                && result.entryShape.rawValue == manifest.expected.entryShape
            if manifest.acceptance != "ready" {
                report.append("  pending(\(matches ? "matches" : "differs")): \(manifest.pendingReason)")
                continue
            }
            if matches == false {
                failures.append(
                    "\(line) | expected status=\(manifest.expected.status) " +
                        "entryShape=\(manifest.expected.entryShape) | \(manifest.note) | " +
                        "missing(\(missing.count))=\(missing)"
                )
            }
        }
        // 中文注释：整份报告总是打印，供归因；只有与验收矩阵不符的站计为失败。
        print("PreflightArchiveFixtureReport policy=\(Self.detailShapePolicy.rawValue) overlap=\(Self.overlapPolicy.rawValue) pub=\(Self.publicationOwnerPolicy.rawValue) chrome=\(Self.chromePolicy.rawValue)\n" + report.joined(separator: "\n"))
        XCTAssertTrue(failures.isEmpty, "与 §13.15 预期不符：\n" + failures.joined(separator: "\n"))
    }

    private func loadManifest(_ site: String) throws -> FixtureManifest {
        let data: Data = try self.loadDocument(site, "manifest.json")
        return try JSONDecoder().decode(FixtureManifest.self, from: data)
    }

    private func loadDocument(_ site: String, _ file: String) throws -> Data {
        let bundle: Bundle = Bundle(for: Self.self)
        let name: String = (file as NSString).deletingPathExtension
        let ext: String = (file as NSString).pathExtension
        // 中文注释：XcodeGen 把非源码文件平铺进测试 bundle 的 Copy Bundle Resources；
        // 先按子目录找，再退回平铺查找。
        if let url: URL = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "PreflightFixtures/\(site)"
        ) {
            return try Data(contentsOf: url)
        }
        if let url: URL = bundle.url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }
        throw XCTSkip("fixture \(site)/\(file) 不在测试 bundle 里；先运行 scripts/regenerate-project.sh")
    }
}
