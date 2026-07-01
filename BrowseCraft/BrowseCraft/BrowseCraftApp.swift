//
//  BrowseCraftApp.swift
//  BrowseCraft
//
//  Created by 谢飞 on 2026/07/02.
//

import SwiftUI

@main
struct BrowseCraftApp: App {
    private let container: AppContainer = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: self.container)
        }
    }
}
