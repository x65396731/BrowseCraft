import SwiftUI
import UIKit

/// 中文注释：书库卡片标题的颜色。漫画卡片与影片网格原先各自写死深蓝 (21, 30, 71)，
/// 深色模式下压在黑底上几乎看不见；收成一个随外观切换的颜色，浅色模式保持原取值，深色模式换成接近白色的浅灰。
/// 列表标签栏不用它：未选中的标签底色固定是白色，文字必须一直是深色。
extension Color {
    static let libraryTitleText: Color = Color(
        uiColor: UIColor { traits in
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 236 / 255, green: 238 / 255, blue: 245 / 255, alpha: 1)
                : UIColor(red: 21 / 255, green: 30 / 255, blue: 71 / 255, alpha: 1)
        }
    )
}
