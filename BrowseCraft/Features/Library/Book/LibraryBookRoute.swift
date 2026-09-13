import Foundation

// 中文注释：本地书在 Library 导航栈里的两级路由：书架、某本书。只在 LibraryView 的栈根声明一次
// navigationDestination——SwiftUI 只认离根最近的那个声明，书架内部再声明第二级会被忽略（2026-09-14 模拟器实测）。

enum LibraryBookRoute: Hashable {
    case shelf
    case book(LocalBook)
}
