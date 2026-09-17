import Foundation
import BrowseCraftCore
@testable import BrowseCraft
import BrowseCraftDomain

// 中文注释：ViewModel 测试用的可编排 runtime：list / reader 行为由闭包决定，并记录每次输入，
// 让测试既能断言 ViewModel 状态，也能断言它向 runtime 发出的请求。
final class ScriptedSourceRuntime: SourceRuntime, SourceReaderRuntime, SourceSearchRuntime, @unchecked Sendable {
    typealias ListHandler = @Sendable (SourceListInput) async throws -> SourceListOutput
    typealias SearchHandler = @Sendable (SourceSearchInput) async throws -> SourceListOutput
    /// 中文注释：默认不支持搜索；测试按需打开并挂上 searchHandler。
    var supportsSearch: Bool = false
    private var searchHandler: SearchHandler = { input in
        throw SourceRuntimeError.unsupported(.custom("Search is not scripted for \(input.keyword)."))
    }
    private var recordedSearchInputs: [SourceSearchInput] = []
    typealias ReaderHandler = @Sendable (SourceReaderInput) async throws -> SourceReaderOutput

    let definition: SourceDefinition
    private let lock: NSLock = NSLock()
    private var listHandler: ListHandler
    private var readerHandler: ReaderHandler
    private var recordedListInputs: [SourceListInput] = []
    private var recordedReaderInputs: [SourceReaderInput] = []

    init(
        definition: SourceDefinition,
        list: @escaping ListHandler = { _ in ScriptedSourceRuntime.emptyListOutput },
        reader: @escaping ReaderHandler = { input in
            throw SourceRuntimeError.unsupported(
                .custom("Reader is not scripted for \(input.chapterURL.absoluteString).")
            )
        }
    ) {
        self.definition = definition
        self.listHandler = list
        self.readerHandler = reader
    }

    convenience init(
        source: Source,
        list: @escaping ListHandler = { _ in ScriptedSourceRuntime.emptyListOutput },
        reader: @escaping ReaderHandler = { input in
            throw SourceRuntimeError.unsupported(
                .custom("Reader is not scripted for \(input.chapterURL.absoluteString).")
            )
        }
    ) {
        self.init(
            definition: SourceDefinitionMapper().definition(from: source),
            list: list,
            reader: reader
        )
    }

    var capabilities: SourceRuntimeCapabilities {
        return SourceRuntimeCapabilities(
            supportsSearch: self.supportsSearch,
            supportsPagination: true,
            supportsDetail: false,
            supportsReader: true,
            supportsDebug: false,
            supportsCandidateAnalysis: false,
            requiresWebView: false,
            requiresCookieStore: false,
            requiresAccount: false
        )
    }

    var listInputs: [SourceListInput] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedListInputs
    }

    var readerInputs: [SourceReaderInput] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedReaderInputs
    }

    func setListHandler(_ handler: @escaping ListHandler) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.listHandler = handler
    }

    func setReaderHandler(_ handler: @escaping ReaderHandler) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.readerHandler = handler
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        // 中文注释：async 函数里不能直接 lock()/unlock()（跨 await 持锁风险），用作用域锁一次取出快照。
        let handler: ListHandler = self.lock.withLock {
            self.recordedListInputs.append(input)
            return self.listHandler
        }
        return try await handler(input)
    }

    func setSearchHandler(_ handler: @escaping SearchHandler) {
        self.lock.lock()
        self.searchHandler = handler
        self.lock.unlock()
    }

    var searchInputs: [SourceSearchInput] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedSearchInputs
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        let handler: SearchHandler = self.lock.withLock {
            self.recordedSearchInputs.append(input)
            return self.searchHandler
        }
        return try await handler(input)
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        let handler: ReaderHandler = self.lock.withLock {
            self.recordedReaderInputs.append(input)
            return self.readerHandler
        }
        return try await handler(input)
    }

    static let emptyListOutput: SourceListOutput = SourceListOutput(
        items: [],
        pagination: nil,
        diagnostics: .succeeded()
    )

    static func listOutput(
        ids: [String],
        baseURL: String = "https://example.test",
        nextPage: Int? = nil
    ) -> SourceListOutput {
        return SourceListOutput(
            items: ids.map { id in
                SourceContentItem(
                    id: id,
                    title: "Item \(id)",
                    detailURL: URL(string: "\(baseURL)/item/\(id)"),
                    coverURL: nil,
                    latestText: nil
                )
            },
            pagination: nextPage.map { page in
                SourcePagination(nextPageURL: nil, nextPage: page)
            },
            diagnostics: .succeeded()
        )
    }

    static func readerOutput(
        sourceID: String,
        chapterURL: URL,
        imageURLs: [URL],
        previousChapterURL: URL? = nil,
        nextChapterURL: URL? = nil
    ) -> SourceReaderOutput {
        return SourceReaderOutput(
            chapter: SourceReaderChapter(
                sourceID: sourceID,
                chapterURL: chapterURL,
                previousChapterURL: previousChapterURL,
                nextChapterURL: nextChapterURL,
                imageURLs: imageURLs
            ),
            diagnostics: .succeeded()
        )
    }
}
