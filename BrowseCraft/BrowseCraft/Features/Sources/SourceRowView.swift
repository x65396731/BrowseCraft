import SwiftUI

// 中文注释：SourceRowView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：SourceRowView 是 struct，负责本模块中的对应职责。
struct SourceRowView: View {
    let source: Source
    let isSelected: Bool
    let isLoading: Bool
    let isDisabled: Bool
    let selectAction: () -> Void

    var body: some View {
        Button(
            action: {
                self.selectAction()
            },
            label: {
                HStack(spacing: 12) {
                    if self.isLoading {
                        ProgressView()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: self.isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(self.isSelected ? .green : .secondary)
                            .frame(width: 24, height: 24)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(self.source.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(self.source.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Text(self.source.isBuiltIn ? "Built-in rule" : "User rule")
                            .font(.caption2)
                            .foregroundColor(self.source.isBuiltIn ? .blue : .secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        )
        .buttonStyle(.plain)
        .disabled(self.isDisabled)
        .opacity(self.isDisabled && self.isLoading == false ? 0.55 : 1)
    }
}
