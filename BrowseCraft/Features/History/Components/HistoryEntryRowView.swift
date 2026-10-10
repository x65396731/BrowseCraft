import BrowseCraftCore
import BrowseCraftDomain
import SwiftUI

/// 历史卡片行：封面（左下角类型徽标，视频底边进度条）+ 作品名 / 看到哪里 / 「来源 · 时刻」+ ›。
/// 同一天的行拼成一张圆角 18 的卡片；日期由分组头承担，行内只写时刻。
struct HistoryEntryRowView: View {
    let entry: ReadingHistoryEntry
    let progressText: String?
    let playbackProgress: Double?
    let sourceName: String
    let sourceState: HistoryViewModel.SourceState
    let coverURL: String?
    let refererURL: String?
    let imageRequestConfig: RequestConfig?
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 12) {
                ContentCoverView(
                    urlString: self.coverURL,
                    refererURLString: self.refererURL,
                    requestConfig: self.imageRequestConfig,
                    kind: HistoryViewModel.catalogKind(of: self.entry),
                    progress: self.playbackProgress
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let progressText: String = self.progressText {
                        Text(progressText)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    self.metaLine
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if self.sourceState != .unknown {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .opacity(self.isDimmed ? 0.5 : 1)
            .contentCardGroupRow(isFirst: self.isFirst, isLast: self.isLast)
        }
        .buttonStyle(.plain)
    }

    private var isDimmed: Bool {
        return self.sourceState == .deleted || self.sourceState == .unknown
    }

    @ViewBuilder
    private var metaLine: some View {
        let time: String = " · " + self.entry.visitedAt.formatted(date: .omitted, time: .shortened)
        switch self.sourceState {
        case .paused:
            Text(self.sourceName).foregroundStyle(.secondary)
                + Text(NSLocalizedString("favorites_source_paused_suffix", comment: "")).foregroundStyle(CatalogPalette.warning)
                + Text(time).foregroundStyle(.secondary)
        case .deleted:
            Text(self.sourceName + NSLocalizedString("favorites_source_deleted_suffix", comment: "") + time)
                .foregroundStyle(.secondary)
        case .available, .unknown, .temporary:
            Text(self.sourceName + time)
                .foregroundStyle(.secondary)
        }
    }
}

/// 继续卡片：当前筛选下最近的一条，放大成该条类型的深色色块（与来源页「正在使用」瓷砖同一种语言）。
/// 顶部一行强调色小字「上次看到 / 上次读到」，不放按钮——整张卡片就是点击区，与点列表行同一条路径。
struct HistoryContinueTileView: View {
    let entry: ReadingHistoryEntry
    let progressText: String?
    let playbackProgress: Double?
    let sourceName: String
    let sourceState: HistoryViewModel.SourceState
    let coverURL: String?
    let refererURL: String?
    let imageRequestConfig: RequestConfig?
    /// 中文注释：底行文字；nil 时按历史页的写法「来源 · 时刻」。库页的「上次看到」瓷砖只写时刻——来源名已是大标题
    /// （`docs/design/Library-Video-Page-Redesign-Design.md` 第六节）。
    var metaTextOverride: String? = nil
    /// 中文注释：第一行小字；nil 时按类型写「上次看到」/「上次读到」。库页整站有声的来源传「上次听到」
    /// （`docs/design/Library-Book-Page-Redesign-Design.md` 第六节）。
    var titleTextOverride: String? = nil
    let action: () -> Void

    var body: some View {
        let kind: CatalogSourceKind = HistoryViewModel.catalogKind(of: self.entry)
        let style: CatalogKindStyle = CatalogKindStyle.of(kind)
        Button(action: self.action) {
            HStack(spacing: 14) {
                ContentCoverView(
                    urlString: self.coverURL,
                    refererURLString: self.refererURL,
                    requestConfig: self.imageRequestConfig,
                    kind: kind,
                    width: 72,
                    height: 100,
                    cornerRadius: 12,
                    badge: .tile
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(self.titleTextOverride ?? (kind == .video
                        ? NSLocalizedString("history_continue_watched", comment: "")
                        : NSLocalizedString("history_continue_read", comment: "")))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(style.bannerAccent)
                    Text(self.entry.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(CatalogKindStyle.bannerTitle)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let progressText: String = self.progressText {
                        Text(progressText)
                            .font(.footnote)
                            .foregroundStyle(style.bannerSecondaryText)
                            .lineLimit(1)
                    }
                    if let progress: Double = self.playbackProgress {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(CatalogPalette.onDarkFill)
                                Capsule()
                                    .fill(style.bannerAccent)
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                        .accessibilityHidden(true)
                    }
                    Text(self.metaText)
                        .font(.caption)
                        .foregroundStyle(style.bannerSecondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .opacity(self.sourceState == .deleted || self.sourceState == .unknown ? 0.6 : 1)
            .sourceTile(style: style)
        }
        .buttonStyle(.plain)
    }

    private var metaText: String {
        if let override: String = self.metaTextOverride {
            return override
        }
        var text: String = self.sourceName
        switch self.sourceState {
        case .paused:
            text += NSLocalizedString("favorites_source_paused_suffix", comment: "")
        case .deleted:
            text += NSLocalizedString("favorites_source_deleted_suffix", comment: "")
        case .available, .unknown, .temporary:
            break
        }
        return text + " · " + self.entry.visitedAt.formatted(date: .omitted, time: .shortened)
    }
}
