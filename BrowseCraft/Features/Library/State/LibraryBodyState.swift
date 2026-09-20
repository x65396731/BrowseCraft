import Foundation

// 中文注释：LibraryBodyState 是 Library 正文的唯一状态轴，取代此前散在 View 里的多条 if 链。

/// 中文注释：Library 正文在同一时刻只有一种呈现。此前这件事由 `libraryContent` 的 if 分支和
/// `.overlay` 的 if 链**各自**判断，两边都看 `items.isEmpty`，于是任何一次空列表加载都会同时
/// 渲染「正在载入」和「没有内容」两块占位（2026-09-20 真机截图）。收敛成一个枚举之后，
/// View 只能 switch 出其中一种，以后再加状态也由编译器逼着在同一处处理。
///
/// 判定顺序即优先级，见 `LibraryViewModel.bodyState`：切源 → 首屏加载 → 失败 → 空 → 有内容。
enum LibraryBodyState: Equatable {
    /// 中文注释：切源途中且屏上还留着上一个站点的列表。这是唯一需要遮罩的场景——
    /// 遮罩是为了挡住屏上的**旧数据**，不是为了表示"正在加载"。
    case switchingSource(sourceName: String)
    /// 中文注释：一条都没有且正在取第 1 页，走骨架网格。
    case loadingFirstPage
    /// 中文注释：一条都没有且当前 tab 报了错。有内容时错误改挂正文上方的横幅，不进这个状态。
    case failed(message: String)
    /// 中文注释：取回来就是空的（不在加载、也没报错）。
    case empty
    /// 中文注释：有内容。有内容时的刷新与翻页都不占版面，交给下拉刷新控件和底部分页状态条。
    case content
}
