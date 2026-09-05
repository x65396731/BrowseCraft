import Foundation
import Testing
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

/// `origin` 在 Source ↔ SourceRecord ↔ 云端载荷之间往返不丢，旧行（NULL）读回为 nil。
struct SourceRecordOriginTests {
    private typealias Harness = ViewModelTestHarness

    @Test func personalGenerationOriginSurvivesRecordRoundTrip() throws {
        var source: Source = try Harness.makeComicSource(id: "kpkuang-org--vodtype-1")
        source.origin = .personalGeneration

        let record: SourceRecord = try SourceRecord(source: source)
        #expect(record.origin == "personal-generation")
        #expect(try record.domainModel().origin == .personalGeneration)

        let payload: SourceCloudPayload = SourceCloudPayload(record: record)
        #expect(payload.origin == "personal-generation")
        #expect(try SourceRecord(payload: payload).domainModel().origin == .personalGeneration)
    }

    @Test func missingOriginReadsBackAsNil() throws {
        let source: Source = try Harness.makeComicSource(id: "comic.plain")
        let record: SourceRecord = try SourceRecord(source: source)
        #expect(record.origin == nil)
        #expect(try record.domainModel().origin == nil)
    }

    @Test func originIsPersistedAndReloadedThroughTheRepository() throws {
        let database: AppDatabase = try Harness.makeDatabase()
        let repository: GRDBSourceRepository = GRDBSourceRepository(database: database)
        var personal: Source = try Harness.makeComicSource(id: "personal.one", name: "Personal")
        personal.origin = .personalGeneration
        // 中文注释：测试用户只有 1 个站点位；对照来源停用着种进去。
        var plain: Source = try Harness.makeComicSource(id: "plain.one", name: "Plain")
        plain.enabled = false

        try repository.saveSource(personal)
        try repository.saveSource(plain)

        let reloaded: [Source] = try repository.fetchSources()
        #expect(reloaded.first(where: { $0.id == "personal.one" })?.origin == .personalGeneration)
        #expect(reloaded.first(where: { $0.id == "plain.one" })?.origin == nil)
    }
}
