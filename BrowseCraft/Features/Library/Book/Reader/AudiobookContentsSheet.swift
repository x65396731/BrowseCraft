import SwiftUI

// 中文注释：有声书播放页右上「目录」弹出的 sheet（docs/design/Audiobook-Player-Page-Redesign-Design.md 第五节）。
// 只有集列表，有声书不设书签（裁定 8 = C）；随播放页用深色。卡片行组：序号 + 集名，当前集青绿底 + 波形，打开时滚到当前集；
// 超过 100 集顶部用分段芯片（`LibraryChipBar`，每 100 集一段）；本次打开里取不到的集标「已失效」。

struct AudiobookContentsSheet: View {
    let viewModel: BookReaderViewModel
    let dismissAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var selectedSegment: Int?

    private static let segmentSize: Int = 100

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                self.header
                if self.segmentCount > 1 {
                    LibraryChipBar(
                        chips: (0..<self.segmentCount).map { segment in
                            LibraryChipBar<Int>.Chip(
                                id: segment,
                                title: self.segmentTitle(segment),
                                isSelected: segment == (self.selectedSegment ?? self.currentSegment)
                            )
                        },
                        style: CatalogKindStyle.of(.book),
                        background: Color.clear,
                        selectAction: { segment in
                            self.selectedSegment = segment
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(segment * Self.segmentSize, anchor: .top)
                            }
                        }
                    )
                    .padding(.top, 12)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<self.viewModel.audioChapterCount, id: \.self) { index in
                            self.row(index)
                                .id(index)
                        }
                    }
                    .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .background(CatalogPalette.pageBackground)
            .onAppear {
                proxy.scrollTo(self.viewModel.audioChapterIndex, anchor: .center)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: self.dismissAction) {
                Text(NSLocalizedString("Close", comment: "关闭"))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(CatalogPalette.cardBackground, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(NSLocalizedString("Contents", comment: "目录"))
                    .font(.largeTitle.weight(.heavy))
                Text(String(format: NSLocalizedString("audiobook_contents_count", comment: "目录：N 集"), self.viewModel.audioChapterCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func row(_ index: Int) -> some View {
        let isCurrent: Bool = index == self.viewModel.audioChapterIndex
        let accent: Color = CatalogKindStyle.of(.book).accent
        let isGone: Bool = self.viewModel.audioChapterFailures[index] == .gone
        return VStack(spacing: 0) {
            Button {
                self.dismissAction()
                Task { await self.viewModel.playAudioChapter(at: index) }
            } label: {
                HStack(spacing: 0) {
                    Text(verbatim: String(index + 1))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isCurrent ? accent : .secondary)
                        .frame(width: 36, alignment: .leading)
                    Text(self.title(at: index))
                        .font(.subheadline.weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? accent : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isGone {
                        Text(NSLocalizedString("audiobook_contents_gone", comment: "目录：这一集已失效"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isCurrent {
                        Image(systemName: "waveform")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .symbolEffect(
                                .variableColor.iterative,
                                isActive: self.viewModel.audioPlayback.state == .playing && self.reduceMotion == false
                            )
                            .accessibilityLabel(NSLocalizedString("audiobook_contents_now_playing", comment: "读屏：正在听"))
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(isCurrent ? accent.opacity(0.16) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if index < self.viewModel.audioChapterCount - 1 {
                Rectangle()
                    .fill(CatalogPalette.separator)
                    .frame(height: 0.5)
                    .padding(.leading, 52)
            }
        }
    }

    private func title(at index: Int) -> String {
        let titles: [String?] = self.viewModel.audioChapterTitles
        if titles.indices.contains(index),
           let title: String = titles[index]?.trimmingCharacters(in: .whitespacesAndNewlines),
           title.isEmpty == false {
            return title
        }
        return String(format: NSLocalizedString("audiobook_player_episode_fallback", comment: "第 N 集"), index + 1)
    }

    private var segmentCount: Int {
        let count: Int = self.viewModel.audioChapterCount
        return count > Self.segmentSize ? (count + Self.segmentSize - 1) / Self.segmentSize : 0
    }

    private var currentSegment: Int {
        return self.viewModel.audioChapterIndex / Self.segmentSize
    }

    private func segmentTitle(_ segment: Int) -> String {
        let start: Int = segment * Self.segmentSize + 1
        let end: Int = min((segment + 1) * Self.segmentSize, self.viewModel.audioChapterCount)
        return "\(start)–\(end)"
    }
}
