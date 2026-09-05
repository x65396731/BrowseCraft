//
//  BrowseCraftApp.swift
//  BrowseCraft
//
//  Created by 谢飞 on 2026/07/02.
//

import SwiftUI
import GoogleMobileAds
import FirebaseCore
import UserNotifications

// 中文注释：BrowseCraftApp.swift 属于应用源码，用于说明本文件承载的核心职责。

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var cloudRemoteNotificationHandler: (() async -> UIBackgroundFetchResult)?
    private var pushDeviceTokenHandler: ((String) async -> Void)?
    private var ruleGenerationPushHandler: ((Bool) -> Void)?
    /// 中文注释：推送可能在容器装配前就被点开（冷启动）；先记下，handler 接上时补发一次。
    private var pendingRuleGenerationPushOpened: Bool?
    /// 中文注释：APNs 通常在容器装配完成前就交回 token；先暂存，handler 接上时补发一次。
    private var latestPushDeviceToken: String?

    func setCloudRemoteNotificationHandler(
        _ handler: @escaping () async -> UIBackgroundFetchResult
    ) {
        self.cloudRemoteNotificationHandler = handler
    }

    func setRuleGenerationPushHandler(_ handler: @escaping (Bool) -> Void) {
        self.ruleGenerationPushHandler = handler
        if let opened: Bool = self.pendingRuleGenerationPushOpened {
            self.pendingRuleGenerationPushOpened = nil
            handler(opened)
        }
    }

    private func handleRuleGenerationPush(userInfo: [AnyHashable: Any], opened: Bool) {
        guard RuleGenerationPushPayload.isRuleGenerationOutcome(userInfo) else {
            return
        }
        AppLog.notice(
            .push,
            event: opened ? "outcome-push-opened" : "outcome-push-presented",
            metadata: ["status": (userInfo[RuleGenerationPushPayload.statusKey] as? String) ?? "unknown"]
        )
        guard let handler: (Bool) -> Void = self.ruleGenerationPushHandler else {
            // 中文注释：点开优先于到达——冷启动时两者都可能先于装配到来。
            self.pendingRuleGenerationPushOpened = (self.pendingRuleGenerationPushOpened ?? false) || opened
            return
        }
        handler(opened)
    }

    func setPushDeviceTokenHandler(_ handler: @escaping (String) async -> Void) {
        self.pushDeviceTokenHandler = handler
        guard let deviceToken: String = self.latestPushDeviceToken else {
            return
        }
        Task { @MainActor in
            await handler(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        CrashDiagnostics.shared.configure()
        AppAnalytics.shared.configure()
        AppAnalytics.shared.logAppOpen()
        // 中文注释：delegate 必须在启动完成前设好，否则前台收到的 alert 推送不会显示。
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    /// 中文注释：token 转小写十六进制，与 PortalCore `/v1/push/devices` 的校验形状一致；
    /// token 是设备标识，不进日志（AGENTS.md §2.6）。
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        _ = application
        let token: String = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.latestPushDeviceToken = token
        guard let handler: (String) async -> Void = self.pushDeviceTokenHandler else {
            return
        }
        Task { @MainActor in
            await handler(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        _ = application
        AppLog.error(
            .push,
            event: "remote-notification-registration-failed",
            metadata: ["error": AppLog.safeErrorCode(error)]
        )
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// 中文注释：App 在前台时系统默认不显示横幅；规则生成完成的通知在前台同样要可见，
    /// 且到达即刷新目录（用户不必再点横幅）。
    ///
    /// 用 completionHandler 形式而不是 async：async 形式在 `await MainActor.run` 之后回到
    /// 后台执行器结束，系统桥接的 completion 便在后台线程被调，UIKit 随即以
    /// `Call must be made on main thread` 断言崩溃（09-05 真机点开推送时复现）。
    /// completion 必须在主线程调用。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        _ = center
        let userInfo: [AnyHashable: Any] = notification.request.content.userInfo
        DispatchQueue.main.async {
            self.handleRuleGenerationPush(userInfo: userInfo, opened: false)
            completionHandler([.banner, .list, .sound])
        }
    }

    /// 中文注释：用户点开推送（后台或已退出）→ 刷新目录，让新规则出现在「我的生成」里。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = center
        let userInfo: [AnyHashable: Any] = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            self.handleRuleGenerationPush(userInfo: userInfo, opened: true)
            completionHandler()
        }
    }
}

@main
/// 中文注释：BrowseCraftApp 是 struct，负责本模块中的对应职责。
struct BrowseCraftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var bootstrapState: AppBootstrapState = .loading

    init() {
        if AppAdConfiguration.hasAdMobApplicationID {
            MobileAds.shared.start()
        } else {
            #if DEBUG
            AppDebugLog.write("[BrowseCraftAds] skip MobileAds.start because GADApplicationIdentifier is missing")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            switch self.bootstrapState {
            case .loading:
                ProgressView("Opening BrowseCraft…")
                    .task {
                        guard case .loading = self.bootstrapState else {
                            return
                        }
                        self.bootstrapState = await AppBootstrapState.bootstrap()
                    }
            case .ready(let container):
                RootView(container: container)
                    .task {
                        self.delegate.setCloudRemoteNotificationHandler {
                            do {
                                let result: CloudSyncRunResult = try await container
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
                        self.delegate.setPushDeviceTokenHandler { deviceToken in
                            await container.handlePushDeviceToken(deviceToken)
                        }
                        self.delegate.setRuleGenerationPushHandler { opened in
                            container.handleRuleGenerationPushNotification(opened: opened)
                        }
                        await container.startApplicationServices()
                    }
                    .onChange(of: self.scenePhase) { _, phase in
                        guard phase == .active else {
                            return
                        }
                        Task {
                            await container.handleAppBecameActive()
                        }
                    }
            case .failed(let failure):
                AppBootstrapFailureView(failure: failure)
            }
        }
    }
}
