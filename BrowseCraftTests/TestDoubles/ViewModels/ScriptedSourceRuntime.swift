import Foundation
import BrowseCraftCore
@testable import BrowseCraft

// 中文注释：ViewModel 测试用的可编排 runtime：list / reader 行为由闭包决定，并记录每次输入，
// 让测试既能断言 ViewModel 状态，也能断言它向 runtime 发出的请求。
final class ScriptedSourceRuntime: SourceRuntime, SourceReaderRuntime, @unchecked Sendable {
    typealias ListHandler = @Sendable (SourceListInput) async throws -> SourceListOutput
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
            supportsSearch: false,
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
        self.lock.lock()
        self.recordedListInputs.append(input)
        let handler: ListHandler = self.listHandler
        self.lock.unlock()
        return try await handler(input)
    }

    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        self.lock.lock()
        self.recordedReaderInputs.append(input)
        let handler: ReaderHandler = self.readerHandler
        self.lock.unlock()
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
