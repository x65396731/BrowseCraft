//
//  BrowseCraftApp.swift
//  BrowseCraft
//
//  Created by 谢飞 on 2026/07/02.
//

import SwiftUI
import GoogleMobileAds
import FirebaseCore

// 中文注释：BrowseCraftApp.swift 属于应用源码，用于说明本文件承载的核心职责。

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        CrashDiagnostics.shared.configure()
        return true
    }
}

@main
/// 中文注释：BrowseCraftApp 是 struct，负责本模块中的对应职责。
struct BrowseCraftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let container: AppContainer = AppContainer()

    init() {
        if AppAdConfiguration.hasAdMobApplicationID {
            MobileAds.shared.start()
        } else {
            #if DEBUG
            print("[BrowseCraftAds] skip MobileAds.start because GADApplicationIdentifier is missing")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: self.container)
        }
    }
}
