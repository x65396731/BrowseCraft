import SwiftUI

// 中文注释：EmptyStateView.swift 属于共享界面组件层，用于说明本文件承载的核心职责。

/// 中文注释：EmptyStateView 是 struct，负责本模块中的对应职责。
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    /// 中文注释：空状态插画的资产名。给了就画插画，没给就退回 `systemImage` 的系统符号——
    /// 不是每一处空态都配了插画（生成失败那一屏至今没有落点），退路必须留着。
    var illustration: String?

    var body: some View {
        VStack(spacing: 12) {
            EmptyStateIconView(systemImage: self.systemImage, illustration: self.illustration)

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

/// 中文注释：空态的图面。插画按 180pt 高渲染——资产是 540px 高，正好是 @3x 的原生分辨率；
/// 宽度随各张自己的宽高比走（0.51 到 0.94），所以用 `.scaledToFit()` 装进等高的框，
/// 窄的那几张左右留白多一些，而不是把它们拉宽。
/// 插画自身不含说明性内容，读屏时由外层 `title` / `message` 承担，因此对辅助功能隐藏。
struct EmptyStateIconView: View {
    let systemImage: String
    let illustration: String?

    var body: some View {
        if let name: String = self.illustration {
            Image(name)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 180)
                .accessibilityHidden(true)
        } else {
            Image(systemName: self.systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundColor(.secondary)
        }
    }
}
