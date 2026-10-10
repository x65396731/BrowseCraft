import Foundation
import Observation

/// 分段芯片：按显示顺序每 50 章一段，`id` 是段首章节 URL，点了滚到那一行。漫画详情与书详情共用
/// （2026-10-11 复审「跨页复制」收敛，此前两个 ViewModel 各一份 `makeSegments` 与同一套选中 / 滚动状态）。
struct ChapterSegment: Identifiable, Hashable {
    let id: String
    let title: String
    let chapterURLs: Set<String>
}

/// 能被分段的目录条目：`id` 是章节 URL，`numberLabel` 是解出的编号（解不出 nil），`ordinal` 是显示顺序的序号。
protocol ChapterSegmentEntry: Identifiable where ID == String {
    var numberLabel: String? { get }
    var ordinal: Int { get }
}

enum ChapterSegmentation {
    /// ≥ 60 章时按显示顺序每 50 章一段；芯片文字是段首与段尾的编号（解不出编号用序号）。
    static func makeSegments<Entry: ChapterSegmentEntry>(_ entries: [Entry]) -> [ChapterSegment] {
        guard entries.count >= ComicChapterTitleParser.segmentThreshold else {
            return []
        }
        return stride(from: 0, to: entries.count, by: ComicChapterTitleParser.segmentSize).map { start in
            let end: Int = min(start + ComicChapterTitleParser.segmentSize, entries.count)
            let slice: ArraySlice<Entry> = entries[start..<end]
            let first: Entry = slice.first!
            let last: Entry = slice.last!
            let firstLabel: String = first.numberLabel ?? String(first.ordinal)
            let lastLabel: String = last.numberLabel ?? String(last.ordinal)
            return ChapterSegment(
                id: first.id,
                title: slice.count == 1 ? firstLabel : "\(firstLabel)–\(lastLabel)",
                chapterURLs: Set(slice.map(\.id))
            )
        }
    }
}

/// 分段芯片的选中与滚动锚点状态机：点芯片 → 记下要滚到的段首 → 视图滚完放开 → 之后行的出现再驱动芯片选中。
/// ViewModel 持有一个实例，视图经 ViewModel 的转发属性读它。
@MainActor
@Observable
final class ChapterSegmentSelection {
    /// 点芯片滚动结束后再等这么久才让行的出现回写选中——滚动落定前最后几行的 onAppear 会把芯片抢回去
    /// （漫画详情 2026-10-08 模拟器实测；书详情此前是立即放开，点芯片滚动中途选中可能被抢回，统一为延迟放开）。
    static let releaseDelay: Duration = .milliseconds(600)

    private(set) var segments: [ChapterSegment] = []
    /// 当前选中的分段（段首章节 URL）；nil 表示跟随第一段。
    private(set) var selectedSegmentID: String?
    /// 点分段芯片后要滚到的那一行；视图滚完后清掉。
    private(set) var pendingScrollChapterURL: String?
    /// 点芯片滚动期间不让行的 onAppear 反过来改选中段。
    private var isProgrammaticScrolling: Bool = false
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    var effectiveSelectedSegmentID: String? {
        guard let selected: String = self.selectedSegmentID, self.segments.contains(where: { $0.id == selected }) else {
            return self.segments.first?.id
        }
        return selected
    }

    /// 目录重算后换上新的分段；原选中段不存在了就回到第一段。
    func update(segments: [ChapterSegment]) {
        self.segments = segments
        if let selected: String = self.selectedSegmentID, segments.contains(where: { $0.id == selected }) == false {
            self.selectedSegmentID = segments.first?.id
        } else if self.selectedSegmentID == nil {
            self.selectedSegmentID = segments.first?.id
        }
    }

    /// 翻转显示顺序前清掉选中，重算后回到新顺序的第一段。
    func clearSelection() {
        self.selectedSegmentID = nil
    }

    func select(_ segmentID: String) {
        self.selectedSegmentID = segmentID
        self.isProgrammaticScrolling = true
        self.pendingScrollChapterURL = segmentID
    }

    /// 视图滚到段首之后调用；延迟放开后行的出现才再驱动芯片选中。
    func didFinishProgrammaticScroll() {
        self.pendingScrollChapterURL = nil
        self.releaseTask?.cancel()
        self.releaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.releaseDelay)
            guard Task.isCancelled == false else {
                return
            }
            self?.isProgrammaticScrolling = false
        }
    }

    /// 行或格子出现在屏上：当前滚到哪一段哪个芯片选中。
    func chapterDidAppear(chapterURL: String) {
        guard self.isProgrammaticScrolling == false, self.segments.isEmpty == false else {
            return
        }
        guard let segment: ChapterSegment = self.segments.first(where: { $0.chapterURLs.contains(chapterURL) }),
              segment.id != self.selectedSegmentID else {
            return
        }
        self.selectedSegmentID = segment.id
    }
}

extension ComicChapterEntry: ChapterSegmentEntry {}
extension BookChapterEntry: ChapterSegmentEntry {}
