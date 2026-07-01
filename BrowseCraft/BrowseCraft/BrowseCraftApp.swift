//
//  BrowseCraftApp.swift
//  BrowseCraft
//
//  Created by 谢飞 on 2026/07/02.
//

import SwiftUI

// 中文注释：BrowseCraftApp.swift 属于应用源码，用于说明本文件承载的核心职责。

@main
/// 中文注释：BrowseCraftApp 是 struct，负责本模块中的对应职责。
struct BrowseCraftApp: App {
    private let container: AppContainer = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: self.container)
        }
    }
}
