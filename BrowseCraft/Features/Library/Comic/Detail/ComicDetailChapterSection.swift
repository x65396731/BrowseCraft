import BrowseCraftDomain
import SwiftUI

// 中文注释：漫画详情页的章节目录（`docs/design/Comic-Detail-Page-Redesign-Design.md` 第七、八节）：
// 贴顶分区头（计数、已读、正序 / 倒序、分段芯片）+ 按标题形状二选一的三列网格或行列表，
// 已读变淡、上次读到类型色标记、受限小锁、付费小币；骨架、没有章节与取失败三种状态。

/// 贴顶的分区头：「章节 · N 章 · 已读 M」+ 正序 / 倒序 + 分段芯片。
struct ComicDetailChapterHeader: View {
    let viewModel: ComicDetailViewModel
    let style: CatalogKindStyle

    var body: some View {
        var infoTexts: [String] = []
        if self.viewModel.didLoad, self.viewModel.chapters.isEmpty == false {
            infoTexts.append(String(format: NSLocalizedString("comic_detail_chapter_count", comment: ""), self.viewModel.chapters.count))
            if self.viewModel.readCount > 0 {
                infoTexts.append(String(format: NSLocalizedString("comic_detail_read_count", comment: ""), self.viewModel.readCount))
            }
        }
        return DetailChapterHeader(
            title: NSLocalizedString("comic_detail_section_chapters", comment: ""),
            infoTexts: infoTexts,
            showsOrderToggle: self.viewModel.didLoad && self.viewModel.showsOrderToggle,
            isDescending: self.viewModel.isDisplayDescending,
            toggleOrder: {
                self.viewModel.toggleDisplayOrder()
            },
            segments: self.viewModel.segments,
            selectedSegmentID: self.viewModel.effectiveSelectedSegmentID,
            style: self.style,
            selectSegment: { segmentID in
                self.viewModel.selectSegment(segmentID)
            }
        ) {
            // 中文注释：受限横幅放在贴顶的分区头里——点的是目录里的某一行，横幅得在目录旁边出现；
            // 放在简介下面时目录滚过头部就看不见（2026-10-08 模拟器实测）。
            self.accessBanners

            // 中文注释：已有目录再下拉刷新失败——目录留着，错误用横幅（合同第八节，2026-10-10 裁定）；
            // 目录为空时的失败态由 `ComicDetailChapterSection` 的占位承担。
            if let message: String = self.viewModel.errorMessage,
               self.viewModel.chapters.isEmpty == false {
                LibraryStateBanner(kind: .failure, message: message)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: - 受限横幅（第八节）

    @ViewBuilder
    private var accessBanners: some View {
        if let prompt: ComicDetailSourceLoginPrompt = self.viewModel.sourceLoginPrompt {
            LibraryStateBanner(
                kind: .restricted,
                message: self.viewModel.loginPromptMessage(isPaid: prompt.isPaid),
                loginAction: {
                    self.viewModel.requestSourceLogin(state: prompt.state)
                },
                dismissAction: {
                    self.viewModel.dismissSourceLoginPrompt()
                }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        } else if let message: String = self.viewModel.accessMessage {
            LibraryStateBanner(
                kind: .restricted,
                message: message,
                dismissAction: {
                    self.viewModel.dismissAccessMessage()
                }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

}

/// 目录主体：骨架 / 空 / 失败 / 网格 / 行列表。
struct ComicDetailChapterSection: View {
    let viewModel: ComicDetailViewModel
    let style: CatalogKindStyle
    let selectChapter: (ChapterLink) -> Void

    var body: some View {
        if self.viewModel.didLoad == false, self.viewModel.isLoading {
            self.skeletonRows
        } else if let message: String = self.viewModel.errorMessage, self.viewModel.chapters.isEmpty {
            self.placeholder(
                systemImage: "exclamationmark.triangle",
                tint: CatalogPalette.warning,
                fill: CatalogPalette.warningFill,
                title: NSLocalizedString("video_detail_failed_title", comment: ""),
                message: message
            )
        } else if self.viewModel.didLoad, self.viewModel.chapters.isEmpty {
            self.placeholder(
                systemImage: "list.bullet.rectangle",
                tint: .secondary,
                fill: CatalogPalette.fillBackground,
                title: NSLocalizedString("comic_detail_empty_title", comment: ""),
                message: NSLocalizedString("comic_detail_empty_message", comment: "")
            )
        } else if self.viewModel.usesGrid {
            self.grid
        } else {
            self.rows
        }
    }

    // MARK: - 三列网格（纯编号目录）

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(self.viewModel.displayEntries) { entry in
                self.gridCell(entry)
                    .id(entry.id)
                    .onAppear {
                        self.viewModel.chapterDidAppear(entry)
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// 格子：高 44、圆角 12、卡片底，显示整个标题；已读次级填充 + 对勾；上次读到描边 + 书签；受限 / 付费右上角标。
    private func gridCell(_ entry: ComicChapterEntry) -> some View {
        let isCurrent: Bool = self.viewModel.isCurrent(entry)
        let isRead: Bool = isCurrent == false && self.viewModel.isRead(entry)
        return Button {
            self.selectChapter(entry.chapter)
        } label: {
            Text(entry.chapter.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(isCurrent ? self.style.accent : (isRead ? Color.secondary : Color.primary))
                .background(
                    isRead ? CatalogPalette.fillBackground : CatalogPalette.cardBackground,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(self.style.accent, lineWidth: isCurrent ? 1.5 : 0)
                )
                .overlay(alignment: .topLeading) {
                    if isCurrent {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(self.style.accent)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    self.cornerMark(entry: entry, isRead: isRead)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.accessibilityLabel(entry: entry, isRead: isRead, isCurrent: isCurrent))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder
    private func cornerMark(entry: ComicChapterEntry, isRead: Bool) -> some View {
        if entry.chapter.isRestricted == true {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(5)
                .accessibilityHidden(true)
        } else if entry.chapter.isPaid == true {
            Image(systemName: "yensign.circle.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(5)
                .accessibilityHidden(true)
        } else if isRead {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(5)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 行列表（带名目录）

    private var rows: some View {
        // 中文注释：长篇漫画可能上千章，行必须懒创建，避免详情解析成功后主线程一次性构建全部按钮。
        LazyVStack(spacing: 0) {
            ForEach(Array(self.viewModel.displayEntries.enumerated()), id: \.element.id) { index, entry in
                self.row(entry, showsDivider: index > 0)
                    .id(entry.id)
                    .onAppear {
                        self.viewModel.chapterDidAppear(entry)
                    }
            }
        }
        .background(CatalogPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// 行：编号柱 44 + 标题两行 + 右侧日期 / 页数；已读次级色 + 对勾；上次读到左缘 3pt 竖条 + 类型色标题。
    private func row(_ entry: ComicChapterEntry, showsDivider: Bool) -> some View {
        let isCurrent: Bool = self.viewModel.isCurrent(entry)
        let isRead: Bool = isCurrent == false && self.viewModel.isRead(entry)
        let titleColor: Color = isCurrent ? self.style.accent : (isRead ? Color.secondary : Color.primary)
        let trailingText: String? = isCurrent ? self.viewModel.currentChapterProgressText : TrimmedText.nonEmpty(entry.chapter.subtitle)
        return Button {
            self.selectChapter(entry.chapter)
        } label: {
            VStack(spacing: 0) {
                if showsDivider {
                    Divider()
                        .padding(.leading, 70)
                }
                HStack(alignment: .center, spacing: 10) {
                    Text(entry.columnLabel)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isCurrent ? self.style.accent : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 44, alignment: .leading)

                    Text(entry.rowTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let trailingText: String = trailingText {
                        Text(trailingText)
                            .font(.caption)
                            .foregroundStyle(isCurrent ? self.style.accent : Color.secondary)
                            .lineLimit(1)
                    }

                    if entry.chapter.isRestricted == true {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    } else if entry.chapter.isPaid == true {
                        Image(systemName: "yensign.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    } else if isRead {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 52)
            }
            .overlay(alignment: .leading) {
                if isCurrent {
                    self.style.accent.frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.accessibilityLabel(entry: entry, isRead: isRead, isCurrent: isCurrent))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func accessibilityLabel(entry: ComicChapterEntry, isRead: Bool, isCurrent: Bool) -> String {
        var parts: [String] = [entry.chapter.title]
        if isCurrent {
            parts.append(NSLocalizedString("comic_detail_continue", comment: ""))
        } else if isRead {
            parts.append(NSLocalizedString("comic_detail_read", comment: ""))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - 骨架与占位（第八节）

    /// 不知道版式前一律用 8 行骨架。
    private var skeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CatalogPalette.fillBackground)
                        .frame(width: 32, height: 12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CatalogPalette.fillBackground)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CatalogPalette.fillBackground)
                        .frame(width: 48, height: 10)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
        }
        .padding(.vertical, 4)
        .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .accessibilityHidden(true)
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
