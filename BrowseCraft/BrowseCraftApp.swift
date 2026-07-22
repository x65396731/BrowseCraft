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

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var cloudRemoteNotificationHandler: (() async -> UIBackgroundFetchResult)?

    func setCloudRemoteNotificationHandler(
        _ handler: @escaping () async -> UIBackgroundFetchResult
    ) {
        self.cloudRemoteNotificationHandler = handler
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        CrashDiagnostics.shared.configure()
        AppAnalytics.shared.configure()
        AppAnalytics.shared.logAppOpen()
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        _ = application
        _ = userInfo
        guard let cloudRemoteNotificationHandler: (() async -> UIBackgroundFetchResult) =
            self.cloudRemoteNotificationHandler else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            completionHandler(await cloudRemoteNotificationHandler())
        }
    }
}

@main
/// 中文注释：BrowseCraftApp 是 struct，负责本模块中的对应职责。
struct BrowseCraftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

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
                .task {
                    self.delegate.setCloudRemoteNotificationHandler {
                        do {
                            let result: CloudSyncRunResult = try await self.container
                                .handleCloudRemoteNotification()
                            return result.downloadedCount > 0 || result.deletedCount > 0
                                ? .newData
                                : .noData
                        } catch let error as CloudSyncSessionError
                            where error == .synchronizationDisabled || error == .alreadyRunning {
                            return .noData
                        } catch {
                            return .failed
                        }
                    }
                    await self.container.startCloudAccountMonitoring()
                }
                .onChange(of: self.scenePhase) { _, phase in
                    guard phase == .active else {
                        return
                    }
                    Task {
                        await self.container.handleAppBecameActive()
                    }
                }
        }
    }
}
