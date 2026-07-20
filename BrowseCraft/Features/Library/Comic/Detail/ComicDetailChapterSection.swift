import SwiftUI

struct ComicDetailChapterSection: View {
    let chapters: [ChapterLink]
    let isLoading: Bool
    let didLoad: Bool
    let errorMessage: String?
    let selectChapter: (ChapterLink) -> Void
    let retry: () -> Void

    var body: some View {
        ComicDetailCard(
            title: self.chapters.isEmpty ? "Chapters" : "Chapters · \(self.chapters.count)",
            systemImage: "list.bullet.rectangle"
        ) {
            // 中文注释：长篇漫画可能包含上千章节，必须懒创建行，避免详情解析成功后主线程一次性构建全部按钮。
            LazyVStack(spacing: 0) {
                if self.isLoading && self.didLoad == false {
                    ProgressView("Loading Details")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 150)
                } else if let errorMessage: String = self.errorMessage, self.chapters.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again", action: self.retry)
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else if self.didLoad && self.chapters.isEmpty {
                    ContentUnavailableView(
                        "No Chapters",
                        systemImage: "list.bullet.rectangle",
                        description: Text("This source did not return any chapter entries.")
                    )
                    .frame(minHeight: 170)
                } else {
                    ForEach(Array(self.chapters.enumerated()), id: \.element.url) { index, chapter in
                        Button {
                            self.selectChapter(chapter)
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(index + 1))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chapter.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if let subtitle: String = chapter.subtitle,
                                       subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    if chapter.isPaid == true {
                                        Text("Paid")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: chapter.isRestricted == true ? "lock.fill" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(chapter.isRestricted == true ? Color.orange : Color.secondary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < self.chapters.count - 1 {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 28)
    }
}
