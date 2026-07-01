import Combine
import Foundation

// 中文注释：ReaderViewModel.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ReaderViewModel 是 final class，负责本模块中的对应职责。
final class ReaderViewModel: ObservableObject {
    @Published private(set) var chapter: ReaderChapter?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    let item: ContentItem
    private let source: Source
    private let selectedChapter: ChapterLink?
    private let loadReaderChapterUseCase: LoadReaderChapterUseCase

    init(
        item: ContentItem,
        source: Source,
        selectedChapter: ChapterLink? = nil,
        loadReaderChapterUseCase: LoadReaderChapterUseCase
    ) {
        self.item = item
        self.source = source
        self.selectedChapter = selectedChapter
        self.loadReaderChapterUseCase = loadReaderChapterUseCase
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() async {
        if self.chapter != nil {
            return
        }

        self.isLoading = true
        self.errorMessage = nil

        do {
            let loadedChapter: ReaderChapter = try await self.loadReaderChapterUseCase.execute(
                source: self.source,
                item: self.item,
                chapterURLString: self.selectedChapter?.url
            )
            self.chapter = loadedChapter
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isLoading = false
    }
}

/// 中文注释：ChapterListViewModel 是 final class，负责本模块中的对应职责。
final class ChapterListViewModel: ObservableObject {
    @Published private(set) var chapters: [ChapterLink] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    let item: ContentItem
    let source: Source
    private let loadChaptersUseCase: LoadChaptersUseCase

    init(
        item: ContentItem,
        source: Source,
        loadChaptersUseCase: LoadChaptersUseCase
    ) {
        self.item = item
        self.source = source
        self.loadChaptersUseCase = loadChaptersUseCase
    }

    @MainActor
    /// 中文注释：load 方法封装当前类型的一段业务或界面行为。
    func load() async {
        if self.chapters.isEmpty == false {
            return
        }

        self.isLoading = true
        self.errorMessage = nil

        do {
            let loadedChapters: [ChapterLink] = try await self.loadChaptersUseCase.execute(
                source: self.source,
                item: self.item
            )
            self.chapters = self.sortedChapters(loadedChapters)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isLoading = false
    }

    /// 中文注释：sortedChapters 方法封装当前类型的一段业务或界面行为。
    private func sortedChapters(_ chapters: [ChapterLink]) -> [ChapterLink] {
        return chapters.sorted { lhs, rhs in
            let lhsKey: ChapterSortKey = self.sortKey(for: lhs.title)
            let rhsKey: ChapterSortKey = self.sortKey(for: rhs.title)

            return lhsKey < rhsKey
        }
    }

    /// 中文注释：sortKey 方法封装当前类型的一段业务或界面行为。
    private func sortKey(for title: String) -> ChapterSortKey {
        if let number: Int = self.firstNumber(in: title) {
            return ChapterSortKey(
                hasNumber: true,
                number: number,
                length: title.count,
                title: title
            )
        }

        return ChapterSortKey(
            hasNumber: false,
            number: Int.max,
            length: title.count,
            title: title
        )
    }

    /// 中文注释：firstNumber 方法封装当前类型的一段业务或界面行为。
    private func firstNumber(in text: String) -> Int? {
        var digits: String = ""

        for character: Character in text {
            if character.isNumber {
                digits.append(character)
            } else if digits.isEmpty == false {
                break
            }
        }

        return Int(digits)
    }
}

private struct ChapterSortKey: Comparable {
    var hasNumber: Bool
    var number: Int
    var length: Int
    var title: String

    static func < (lhs: ChapterSortKey, rhs: ChapterSortKey) -> Bool {
        if lhs.hasNumber != rhs.hasNumber {
            return lhs.hasNumber && rhs.hasNumber == false
        }

        if lhs.hasNumber && rhs.hasNumber && lhs.number != rhs.number {
            return lhs.number < rhs.number
        }

        if lhs.length != rhs.length {
            return lhs.length < rhs.length
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
