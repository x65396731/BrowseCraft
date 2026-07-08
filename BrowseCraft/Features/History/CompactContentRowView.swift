import SwiftUI

// 中文注释：CompactContentRowView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：CompactContentRowView 是 struct，负责本模块中的对应职责。
struct CompactContentRowView: View {
    let item: ContentItem
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnailImageView(urlString: self.item.coverURL)
                .frame(width: 48, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(self.item.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text(self.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
