import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation

// 中文注释：LoadBookPublicationUseCase：站点书的作品页 → Runtime 详情 → manifest，并把 Runtime 的 loadBookContent 包成按需取内容的 provider。

struct LoadedBookPublication: Sendable {
    let manifest: BookPublicationManifest
    let contentProvider: BookChapterContentProvider
}

enum LoadBookPublicationError: Error, Equatable, Sendable {
    case runtimeIsNotBookCapable(sourceID: String)
}

/// 中文注释：站点书出版物的短时缓存，由组装层持有一份、详情页与阅读器共用。
/// 2026-09-15 真机日志：每次开书，详情页取一遍作品页 + 目录页，进阅读器又原样取一遍——两边各建一个用例、互不知情。
/// 只缓存成功结果（失败不入缓存，「重试」照常重取），按「来源 id + 作品地址」为键，过期后重取以跟上站点新增章节。
final class BookPublicationCache: @unchecked Sendable {
    private struct Entry {
        let publication: LoadedBookPublication
        let storedAt: Date
    }

    private let lock: NSLock = NSLock()
    private var entries: [String: Entry] = [:]
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date

    init(lifetime: TimeInterval = 300, now: @escaping @Sendable () -> Date = { Date() }) {
        self.lifetime = lifetime
        self.now = now
    }

    func publication(sourceID: String, detailURL: URL) -> LoadedBookPublication? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let key: String = Self.key(sourceID: sourceID, detailURL: detailURL)
        guard let entry: Entry = self.entries[key] else {
            return nil
        }
        guard self.now().timeIntervalSince(entry.storedAt) < self.lifetime else {
            self.entries[key] = nil
            return nil
        }
        return entry.publication
    }

    func store(_ publication: LoadedBookPublication, sourceID: String, detailURL: URL) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.entries[Self.key(sourceID: sourceID, detailURL: detailURL)] = Entry(publication: publication, storedAt: self.now())
    }

    private static func key(sourceID: String, detailURL: URL) -> String {
        return "\(sourceID)\u{1F}\(detailURL.absoluteString)"
    }
}

struct LoadBookPublicationUseCase: Sendable {
    private let runtimeResolver: any SourceRuntimeResolving
    private let assembler: BookPublicationAssembler
    private let cache: BookPublicationCache?

    init(
        runtimeResolver: any SourceRuntimeResolving,
        assembler: BookPublicationAssembler = BookPublicationAssembler(),
        cache: BookPublicationCache? = nil
    ) {
        self.runtimeResolver = runtimeResolver
        self.assembler = assembler
        self.cache = cache
    }

    func execute(source: Source, detailURL: URL) async throws -> LoadedBookPublication {
        if let cached: LoadedBookPublication = self.cache?.publication(sourceID: source.id, detailURL: detailURL) {
            return cached
        }
        let loaded: LoadedBookPublication = try await self.load(source: source, detailURL: detailURL)
        self.cache?.store(loaded, sourceID: source.id, detailURL: detailURL)
        return loaded
    }

    private func load(source: Source, detailURL: URL) async throws -> LoadedBookPublication {
        let runtime: any SourceRuntime = try self.runtimeResolver.runtime(for: source)
        guard let detailRuntime: any SourceDetailRuntime = runtime as? any SourceDetailRuntime,
              let contentRuntime: any SourceBookContentRuntime = runtime as? any SourceBookContentRuntime else {
            throw LoadBookPublicationError.runtimeIsNotBookCapable(sourceID: source.id)
        }
        let context: SourceRuntimeContext = SourceRuntimeContext(
            sourceID: source.id,
            pageID: nil,
            tabID: nil,
            ruleID: nil,
            requestOverride: nil,
            debugMode: false
        )
        let detail: SourceDetailOutput = try await detailRuntime.loadDetail(SourceDetailInput(detailURL: detailURL, context: context, itemReference: nil))
        let manifest: BookPublicationManifest = self.assembler.assemble(source: source, detailURL: detailURL, detail: detail)
        let provider: BookChapterContentProvider = { chapterURL in
            return try await contentRuntime.loadBookContent(SourceBookContentInput(chapterURL: chapterURL, context: context)).content
        }
        return LoadedBookPublication(manifest: manifest, contentProvider: provider)
    }
}
