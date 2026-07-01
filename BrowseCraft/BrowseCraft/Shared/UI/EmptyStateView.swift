import SwiftUI

// 中文注释：EmptyStateView.swift 属于共享界面组件层，用于说明本文件承载的核心职责。

/// 中文注释：EmptyStateView 是 struct，负责本模块中的对应职责。
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundColor(.secondary)

            Text(self.title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(self.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
