import SwiftUI

// 中文注释：ListRowSeparatorAlignment.swift 属于共享界面组件层，统一 List / Form 行分隔线的起点。

/// 中文注释：List 默认把分隔线对齐到行里的第一段**文字**。于是带图标的行（`Label`、
/// `HStack { ProgressView; Text }`）会比同一个 Section 里的纯文本行多缩进一个图标宽度，
/// 同一张卡片里就出现两条起点不同的分隔线（09-05 目录页、09-19 预检页两次真机截图都逮到）。
/// 这不是某个页面的毛病，而是所有「图标 + 文字」行共有的默认值，所以把修法放在这里：
/// 凡是行内有图标的行都挂这个修饰符，分隔线一律钉回行的 leading，Section 内共用同一个起点。
extension View {
    func listRowSeparatorAlignedToRowLeading() -> some View {
        return self.alignmentGuide(.listRowSeparatorLeading) { dimensions in
            return dimensions[.leading]
        }
    }
}
