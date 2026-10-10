import BrowseCraftDomain
import SwiftUI

// 中文注释：站点书详情页的各块（`docs/design/Book-Detail-Page-Redesign-Design.md` 第五到七节）：
// 头部（页面底色上的小封面 + 文字）、继续卡片 / 开始按钮 / 骨架 / 失败横幅、简介；贴顶的章节分区头（章数、正序倒序、分段芯片）；
// 编号柱行列表的目录（上次读到竖条、之前的行变淡）、骨架、没有章节。每一块都是有数据才出。

/// 头部 + 继续卡片 / 开始按钮 + 简介。
struct BookSiteDetailHeaderSection: View {
    let viewModel: BookSiteDetailViewModel
    let style: CatalogKindStyle
    let openSelection: (SiteBookChapterSelection) -> Void
    @State private var isSynopsisExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            self.continueBlock
            self.synopsisSection
        }
        .background(CatalogPalette.pageBackground)
    }

    // MARK: - 头部（第五节）

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            self.cover(width: 72, height: 96, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(self.viewModel.displayTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .accessibilityAddTraits(.isHeader)

                if let author: String = self.viewModel.authorText {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(self.viewModel.sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let countText: String = self.viewModel.chapterCountText {
                    HStack(spacing: 4) {
                        if self.viewModel.isAudiobook {
                            Image(systemName: "headphones")
                                .font(.caption2.weight(.bold))
                                .accessibilityHidden(true)
                        }
                        Text(countText)
                    }
                    .font(.caption)
                    .foregroundStyle(self.viewModel.isAudiobook ? self.style.accent : Color.secondary)
                } else if self.viewModel.isLoading {
                    DetailSkeletonBar(width: 72)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// 封面：manifest 封面 → 列表封面 → 占位图；左缘压 2pt 书脊线，与库页书脊行同一种形状。
    private func cover(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        CoverImageView(
            urlString: self.viewModel.coverURLString,
            refererURLString: self.viewModel.item.detailURL,
            requestConfig: self.viewModel.coverRequestConfig,
            placeholderImageName: "BookCoverPlaceholder"
        )
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(CatalogPalette.coverShade)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .overlay(alignment: .bottomTrailing) {
            if self.viewModel.isAudiobook, width < 60 {
                Image(systemName: "headphones")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CatalogPalette.onAction)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(CatalogPalette.coverScrim))
                    .padding(3)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - 继续卡片 / 开始按钮 / 骨架 / 横幅

    @ViewBuilder
    private var continueBlock: some View {
        if let message: String = self.viewModel.errorMessage, self.viewModel.didLoad == false {
            self.failureBanner(message: message)
        } else if self.viewModel.didLoad == false {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CatalogPalette.fillBackground)
                .frame(height: 88)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .accessibilityHidden(true)
        } else if self.viewModel.hasContinueCard, let title: String = self.viewModel.continueChapterTitle {
            self.continueCard(title: title)
        } else if self.viewModel.chapters.isEmpty == false {
            self.startButton
        }
    }

    /// 继续卡片（共享 `DetailContinueCard`）：小封面带书脊线与有声小圆；文字书「全书 12% · 昨天 21:40」、有声书「12:34 · 昨天 21:40」。
    private func continueCard(title: String) -> some View {
        DetailContinueCard(
            label: self.viewModel.continueLabel,
            title: title,
            subtitle: self.viewModel.continueMetaText,
            progress: self.viewModel.continueProgress,
            iconName: self.viewModel.isAudiobook ? "play.fill" : "book.fill",
            accent: self.style.accent,
            action: {
                self.openSelection(self.viewModel.selection(for: nil))
            }
        ) {
            self.cover(width: 56, height: 72, cornerRadius: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var startButton: some View {
        DetailStartButton(
            iconName: self.viewModel.isAudiobook ? "headphones" : "book.fill",
            title: self.viewModel.startButtonTitle,
            accent: self.style.accent
        ) {
            self.openSelection(self.viewModel.selection(for: self.viewModel.primaryChapter))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    /// 取详情失败：警示色淡底横幅 + 「重试」；来源有登录页时多一个「登录」（第七节）。
    /// 取失败：共享横幅的失败态，来源有登录页时多「登录」（第七节；横幅本身见 `LibraryStateBanner`）。
    private func failureBanner(message: String) -> some View {
        LibraryStateBanner(
            kind: .failure,
            message: message,
            loginAction: self.viewModel.sourceLoginState == nil ? nil : {
                self.viewModel.requestSourceLogin()
            },
            retryAction: {
                Task {
                    await self.viewModel.load()
                }
            }
        )
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - 简介（有才出）

    @ViewBuilder
    private var synopsisSection: some View {
        if let description: String = self.viewModel.descriptionText {
            DetailSynopsisSection(description: description, accent: self.style.accent, isExpanded: self.$isSynopsisExpanded)
        }
    }
}

/// 贴顶的分区头：「章节 · N 章」+ 正序 / 倒序 + 分段芯片（第六节）。
struct BookSiteDetailChapterHeader: View {
    let viewModel: BookSiteDetailViewModel
    let style: CatalogKindStyle

    var body: some View {
        if self.viewModel.didLoad {
            DetailChapterHeader(
                title: NSLocalizedString("comic_detail_section_chapters", comment: ""),
                infoTexts: [String(format: NSLocalizedString("book_detail_chapter_count", comment: ""), self.viewModel.chapterCountNumberText)],
                showsOrderToggle: self.viewModel.showsOrderToggle,
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
            )
        }
    }
}

/// 目录主体：骨架 / 没有章节 / 行列表。
struct BookSiteDetailChapterSection: View {
    let viewModel: BookSiteDetailViewModel
    let style: CatalogKindStyle
    let selectChapter: (BookPublicationItem) -> Void

    var body: some View {
        if self.viewModel.didLoad == false, self.viewModel.errorMessage == nil {
            self.skeletonRows
        } else if self.viewModel.didLoad, self.viewModel.chapters.isEmpty {
            Text(NSLocalizedString("book_detail_empty", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(CatalogPalette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 12)
        } else if self.viewModel.didLoad {
            self.rows
        }
    }

    // MARK: - 行列表

    private var rows: some View {
        // 中文注释：网文上千章，行必须懒创建，避免详情回来后主线程一次性构建全部按钮。
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// 行：编号柱 48（解不出不占位）+ 章名两行 + 上次读到的行尾小字；上次读到左缘 3pt 竖条 + 类型色章名；之前的行变淡。
    private func row(_ entry: BookChapterEntry, showsDivider: Bool) -> some View {
        let isCurrent: Bool = self.viewModel.isCurrent(entry)
        let isRead: Bool = isCurrent == false && self.viewModel.isRead(entry)
        let titleColor: Color = isCurrent ? self.style.accent : (isRead ? Color.secondary : Color.primary)
        return Button {
            self.selectChapter(entry.item)
        } label: {
            VStack(spacing: 0) {
                if showsDivider {
                    Divider()
                        .padding(.leading, 16)
                }
                HStack(alignment: .center, spacing: 0) {
                    if let numberLabel: String = entry.numberLabel {
                        Text(numberLabel)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 48, alignment: .leading)
                    }

                    Text(entry.rowTitle)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(titleColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isCurrent, let trailingText: String = self.viewModel.currentChapterTrailingText {
                        Text(trailingText)
                            .font(.caption)
                            .foregroundStyle(self.style.accent)
                            .lineLimit(1)
                            .padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .leading) {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.style.accent)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BookSiteDetailRowButtonStyle())
        .accessibilityLabel(self.accessibilityLabel(entry: entry, isRead: isRead, isCurrent: isCurrent))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func accessibilityLabel(entry: BookChapterEntry, isRead: Bool, isCurrent: Bool) -> String {
        var parts: [String] = [entry.item.title]
        if isCurrent {
            parts.append(self.viewModel.continueLabel)
        } else if isRead {
            parts.append(NSLocalizedString("comic_detail_read", comment: ""))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - 骨架

    private var skeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CatalogPalette.fillBackground)
                        .frame(width: 28, height: 12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CatalogPalette.fillBackground)
                        .frame(width: [0.7, 0.52, 0.64, 0.46, 0.58, 0.72, 0.5, 0.6][index] * 240, height: 12)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
            }
        }
        .background(CatalogPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .opacity(0.8)
        .accessibilityHidden(true)
    }
}

/// 按下整行底色变 `fillBackground`。
private struct BookSiteDetailRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? CatalogPalette.fillBackground : Color.clear)
    }
}
