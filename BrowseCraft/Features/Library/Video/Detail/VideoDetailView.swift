import BrowseCraftDomain
import SwiftUI
import UIKit

// 中文注释：VideoDetailView 是视频详情和选集页，和漫画章节/Reader 流程分离。
// 版式按 `docs/design/Video-Detail-Page-Redesign-Design.md`：固定深色头图区（海报模糊压暗做底 + 左侧小海报 + 标题区）
// → 通栏「继续看」→ 简介折叠 → 线路芯片 → 集号网格。每一块都是规则真给了数据才出，没有的不留空位。
struct VideoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var viewModel: VideoDetailViewModel
    @State private var isSynopsisExpanded: Bool = false

    private static let headerContentHeight: CGFloat = 236
    private static let posterSize: CGSize = CGSize(width: 108, height: 162)

    init(
        item: ContentItem,
        source: Source,
        factory: LibraryContentViewModelFactory
    ) {
        _viewModel = State(
            wrappedValue: factory.makeVideoDetail(item, source)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    self.header(safeAreaTop: proxy.safeAreaInsets.top)
                    self.continueSection
                    self.synopsisSection
                    self.episodesSection
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
            .scrollBounceBehavior(.always)
        }
        .background(CatalogPalette.pageBackground)
        .navigationTitle(self.viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            CrashDiagnostics.shared.setScreen(.videoDetail)
            AppAnalytics.shared.logScreenView(.videoDetail)
            CrashDiagnostics.shared.setSource(self.viewModel.source)
            CrashDiagnostics.shared.setRuleStage(.detail)
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftVideoDetail] view appear " +
                "source=\(self.viewModel.source.id) " +
                "item=\(self.viewModel.item.id) " +
                "episodes=\(self.viewModel.episodes.count)"
            )
            #endif
        }
        .task {
            #if DEBUG
            AppDebugLog.write(
                "[BrowseCraftVideoDetail] task start " +
                "source=\(self.viewModel.source.id) " +
                "item=\(self.viewModel.item.id)"
            )
            #endif
            // 中文注释：历史与收藏是本地读取，先于网络详情到位——列表取不到时继续看按钮也不缺。
            await self.viewModel.reloadFavoriteState()
            await self.viewModel.reloadContinueWatching()
            await self.viewModel.loadEpisodesIfNeeded()
        }
        .refreshable {
            await self.viewModel.reloadContinueWatching()
            await self.viewModel.loadEpisodes()
        }
        // 中文注释：播放器关闭后重读历史，继续看按钮与集号高亮跟着换。
        .fullScreenCover(
            item: self.$viewModel.playbackRoute,
            onDismiss: {
                Task {
                    await self.viewModel.reloadContinueWatching()
                }
            }
        ) { route in
            VideoPlayerHostView(viewModel: route.viewModel)
        }
    }

    // MARK: - 头图区（第五节）

    private var style: CatalogKindStyle {
        return CatalogKindStyle.of(CatalogSourceKind.video)
    }

    /// 类型色底上的字：浅色白、深色墨。
    private var onAccent: Color {
        return self.colorScheme == .dark ? CatalogKindStyle.bannerIconInk : .white
    }

    private func header(safeAreaTop: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 中文注释：同一张海报放大模糊再压暗做底；没有封面时就是视频深色底。文字都是固定浅色，不随系统变。
            self.style.bannerBackground
                .overlay {
                    ItemThumbnailImageView(
                        urlString: self.viewModel.displayCoverURLString,
                        refererURLString: self.viewModel.item.detailURL,
                        requestConfig: self.viewModel.imageRequestConfig,
                        placeholderImageName: nil
                    )
                    .scaledToFill()
                    .blur(radius: 30)
                    .opacity(0.9)
                }
                .overlay(Color.black.opacity(0.45))
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.clear, CatalogPalette.pageBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                }
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    self.circleButton(systemImage: "chevron.left", label: NSLocalizedString("Back", comment: "")) {
                        self.dismiss()
                    }
                    Spacer(minLength: 0)
                    self.favoriteButton
                }
                .padding(.top, safeAreaTop + 8)
                .padding(.horizontal, 20)

                Spacer(minLength: 12)

                HStack(alignment: .bottom, spacing: 14) {
                    ItemThumbnailImageView(
                        urlString: self.viewModel.displayCoverURLString,
                        refererURLString: self.viewModel.item.detailURL,
                        requestConfig: self.viewModel.imageRequestConfig,
                        placeholderImageName: "VideoDetailPlaceholder"
                    )
                    .frame(width: Self.posterSize.width, height: Self.posterSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(self.viewModel.displayTitle)
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(CatalogKindStyle.bannerTitle)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .accessibilityAddTraits(.isHeader)
                        if let headline: String = self.viewModel.headlineMetadataText {
                            Text(headline)
                                .font(.caption)
                                .foregroundStyle(self.style.bannerSecondaryText)
                                .lineLimit(2)
                        }
                        if let badge: String = self.viewModel.statusBadgeText {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .foregroundStyle(CatalogKindStyle.bannerIconInk)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(self.style.bannerAccent, in: Capsule())
                        }
                        Text(verbatim: "\(self.viewModel.sourceName) · \(self.viewModel.sourceHostText)")
                            .font(.caption)
                            .foregroundStyle(self.style.bannerSecondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minHeight: safeAreaTop + Self.headerContentHeight)
    }

    /// 40pt 圆、白 18% 底；热区补到 44。
    private func circleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(CatalogKindStyle.bannerTitle)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.18), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var favoriteButton: some View {
        Button {
            Task {
                await self.viewModel.toggleFavorite()
            }
        } label: {
            // 中文注释：与库页封面爱心同一对图；已收藏实心用视频强调色。
            Image(self.viewModel.isFavorite ? "TabFavorites" : "TabFavoritesOutline")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundColor(self.viewModel.isFavorite ? self.style.bannerAccent : CatalogKindStyle.bannerTitle)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.18), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            NSLocalizedString(self.viewModel.isFavorite ? "favorites_unfavorite" : "video_detail_favorite", comment: "")
        )
    }

    // MARK: - 继续看（第七节）

    @ViewBuilder
    private var continueSection: some View {
        if self.viewModel.hasLoadedEpisodes == false, self.viewModel.isLoadingEpisodes {
            Capsule()
                .fill(CatalogPalette.fillBackground)
                .frame(height: 50)
                .padding(.horizontal, 20)
                .padding(.top, 16)
        } else if self.viewModel.episodes.isEmpty == false {
            Button {
                Task {
                    await self.viewModel.openContinue()
                }
            } label: {
                HStack(spacing: 8) {
                    if self.viewModel.isResolvingContinue {
                        ProgressView()
                            .tint(self.onAccent)
                        Text(NSLocalizedString("video_detail_resolving", comment: ""))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.bold))
                        Text(self.viewModel.continueButtonTitle)
                        if let subtitle: String = self.viewModel.continueButtonSubtitle {
                            Text(subtitle)
                                .font(.footnote.weight(.medium))
                                .opacity(0.85)
                        }
                    }
                }
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(self.onAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(self.style.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(self.viewModel.isLoadingPlayback)
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - 简介（第四节）

    @ViewBuilder
    private var synopsisSection: some View {
        if self.viewModel.hasLoadedEpisodes == false, self.viewModel.isLoadingEpisodes {
            VStack(alignment: .leading, spacing: 10) {
                self.skeletonBar(width: 36)
                self.skeletonBar(width: nil)
                self.skeletonBar(width: 240)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        } else if self.viewModel.hasSynopsisSection {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("video_detail_section_synopsis", comment: ""))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                if let synopsis: String = self.viewModel.synopsis {
                    Text(synopsis)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(self.isSynopsisExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(self.viewModel.creditLines + self.viewModel.otherMetadataLines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if self.viewModel.synopsis != nil {
                    Button(
                        NSLocalizedString(self.isSynopsisExpanded ? "video_detail_collapse" : "video_detail_expand", comment: "")
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.isSynopsisExpanded.toggle()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(self.style.accent)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }

    private func skeletonBar(width: CGFloat?) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(CatalogPalette.fillBackground)
            .frame(width: width, height: 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 线路与选集（第六节）

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("video_detail_section_episodes", comment: ""))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let line: VideoEpisodeLine = self.viewModel.selectedLine, line.episodes.count >= 2 {
                    Button {
                        self.viewModel.isDescendingOrder.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(String(format: NSLocalizedString("video_detail_episode_count", comment: ""), line.episodes.count))
                            Text(verbatim: "·")
                            Text(NSLocalizedString(
                                self.viewModel.isDescendingOrder ? "video_detail_order_descending" : "video_detail_order_ascending",
                                comment: ""
                            ))
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if self.viewModel.lines.count >= 2 {
                LibraryChipBar(
                    chips: self.viewModel.lines.map { line in
                        LibraryChipBar<String>.Chip(
                            id: line.id,
                            title: line.title ?? "",
                            isSelected: line.id == self.viewModel.selectedLine?.id
                        )
                    },
                    style: self.style,
                    isInteractionDisabled: self.viewModel.isLoadingPlayback,
                    background: .clear,
                    selectAction: { lineID in
                        self.viewModel.selectLine(lineID)
                    }
                )
                .padding(.top, -8)
            }

            if let message: String = self.viewModel.playbackErrorMessage {
                LibraryTabErrorBanner(message: message)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            // 中文注释：已有选集再下拉刷新失败——选集留着，错误用横幅（合同第八节，2026-10-10 裁定），不换成失败占位。
            if let message: String = self.viewModel.detailErrorMessage,
               self.viewModel.episodes.isEmpty == false {
                LibraryTabErrorBanner(message: message)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            self.episodesBody
        }
    }

    @ViewBuilder
    private var episodesBody: some View {
        if self.viewModel.hasLoadedEpisodes == false, self.viewModel.isLoadingEpisodes {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                ForEach(0..<10, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CatalogPalette.fillBackground)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .accessibilityHidden(true)
        } else if let message: String = self.viewModel.detailErrorMessage,
                  self.viewModel.episodes.isEmpty {
            self.placeholder(
                systemImage: "exclamationmark.triangle",
                tint: CatalogPalette.warning,
                fill: CatalogPalette.warningFill,
                title: NSLocalizedString("video_detail_failed_title", comment: ""),
                message: message
            )
        } else if self.viewModel.episodes.isEmpty {
            self.placeholder(
                systemImage: "play.rectangle",
                tint: .secondary,
                fill: CatalogPalette.fillBackground,
                title: NSLocalizedString("video_detail_empty_title", comment: ""),
                message: NSLocalizedString("video_detail_empty_message", comment: "")
            )
        } else if self.viewModel.usesNumericGrid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                ForEach(self.viewModel.visibleEpisodes) { episode in
                    self.episodeCell(episode, expands: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        } else {
            VideoEpisodeFlowLayout(spacing: 10) {
                ForEach(self.viewModel.visibleEpisodes) { episode in
                    self.episodeCell(episode, expands: false)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    /// 集号格子：高 44、圆角 12、卡片底；上次看的那一集类型色描边 + 左上小三角；解析中格内转圈；受限 / 付费右上角标。
    private func episodeCell(_ episode: VideoEpisode, expands: Bool) -> some View {
        let isCurrent: Bool = self.viewModel.continueTargetEpisode == episode
        let isResolving: Bool = self.viewModel.resolvingEpisodeID == episode.id
        return Button {
            Task {
                await self.viewModel.openEpisode(episode)
            }
        } label: {
            ZStack {
                if isResolving {
                    ProgressView()
                        .tint(self.style.accent)
                } else {
                    Text(self.viewModel.displayLabel(for: episode))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, expands ? 6 : 18)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: expands ? CGFloat.infinity : nil)
            .foregroundStyle(isCurrent ? self.style.accent : Color.primary)
            .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.style.accent, lineWidth: isCurrent ? 1.5 : 0)
            )
            .overlay(alignment: .topLeading) {
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(self.style.accent)
                        .padding(5)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if episode.isRestricted == true {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                } else if episode.isPaid == true {
                    Image(systemName: "yensign.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(self.viewModel.isLoadingPlayback)
        .accessibilityLabel(episode.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func placeholder(systemImage: String, tint: Color, fill: Color, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(fill, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 20, weight: .semibold))
                Text(NSLocalizedString("video_detail_pull_retry", comment: ""))
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .accessibilityElement(children: .combine)
    }
}

/// 非数字集名（「HD中字」「正片」）按内容宽排、放不下换行；数字集名走等宽网格，不用它。
struct VideoEpisodeFlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat = proposal.width ?? .infinity
        return self.arrange(subviews: subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement: (size: CGSize, frames: [CGRect]) = self.arrange(subviews: subviews, width: bounds.width)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + self.spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + self.spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - self.spacing)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
