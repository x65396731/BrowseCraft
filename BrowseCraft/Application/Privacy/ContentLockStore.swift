import Foundation
import Observation

/// 收藏与历史锁定的 App 侧状态（`docs/design/Content-Lock-Design.md`）。
///
/// 中文注释：两页共用一个解锁状态——解开其中一页，切到另一页不再验证；进入后台即重新锁定。
/// 非活跃（多任务切换器、控制中心）时只盖上锁定态、不清解锁状态，没进后台就回来时撤掉盖层。
/// 验证本身会让 App 短暂变为非活跃，这一轮非活跃 / 活跃不盖，也不再自动拉起验证，否则取消一次就会无限弹。
@MainActor
@Observable
final class ContentLockStore {
    /// 存下的开关；设备删掉锁屏密码后仍保留，重新设好密码即恢复锁定（设计文档第 2.3 节）。
    private(set) var isEnabledPreference: Bool
    private(set) var method: DeviceOwnerAuthenticationMethod
    private(set) var isUnlocked: Bool = false
    private(set) var isObscured: Bool = false
    private(set) var isAuthenticating: Bool = false
    /// 最近一次解锁没有通过：锁定态显示警示小字。
    private(set) var didLastUnlockFail: Bool = false

    private let authenticator: any DeviceOwnerAuthenticating
    private let preferenceStore: any ContentLockPreferenceStoring
    /// 验证进行中发生的那次非活跃；随后的活跃不触发自动验证。
    @ObservationIgnored private var isSceneTransitionFromAuthentication: Bool = false

    init(
        authenticator: any DeviceOwnerAuthenticating,
        preferenceStore: any ContentLockPreferenceStoring
    ) {
        self.authenticator = authenticator
        self.preferenceStore = preferenceStore
        self.isEnabledPreference = preferenceStore.isContentLockEnabled()
        self.method = authenticator.availableMethod()
    }

    var isAvailable: Bool {
        return self.method != .unavailable
    }

    /// 界面上开关的状态：存下的开启，且这台设备能验证。
    var isEnabled: Bool {
        return self.isEnabledPreference && self.isAvailable
    }

    /// 收藏页与历史页是否盖着锁定态。
    var isContentHidden: Bool {
        return self.isEnabled && (self.isUnlocked == false || self.isObscured)
    }

    func refreshAvailableMethod() {
        self.method = self.authenticator.availableMethod()
    }

    /// 打开与关闭都要先验证一次；通过才改开关，取消或失败时保持原状态（设计文档第 2.3 节）。
    /// 打开时验证通过即视为已解锁。
    func setEnabled(_ enabled: Bool, reason: String) async {
        guard enabled != self.isEnabled,
              self.isAvailable,
              self.isAuthenticating == false else {
            return
        }
        guard await self.authenticate(reason: reason) else {
            return
        }
        self.preferenceStore.setContentLockEnabled(enabled)
        self.isEnabledPreference = enabled
        if enabled {
            self.isUnlocked = true
            self.didLastUnlockFail = false
        }
    }

    func unlock(reason: String) async {
        guard self.isEnabled,
              self.isUnlocked == false,
              self.isAuthenticating == false else {
            return
        }
        if await self.authenticate(reason: reason) {
            self.isUnlocked = true
            self.didLastUnlockFail = false
        } else {
            self.didLastUnlockFail = true
        }
    }

    // MARK: - App 生命周期（由 RootView 转来）

    func sceneDidBecomeInactive() {
        if self.isAuthenticating {
            self.isSceneTransitionFromAuthentication = true
            return
        }
        self.isObscured = true
    }

    func sceneDidEnterBackground() {
        self.isSceneTransitionFromAuthentication = false
        self.isObscured = true
        self.isUnlocked = false
        self.didLastUnlockFail = false
    }

    /// 回到活跃：撤掉盖层并重新问一次能用的验证方式。返回是否应自动拉起验证——
    /// 验证本身引起的那次非活跃 / 活跃不算回到前台。
    @discardableResult
    func sceneDidBecomeActive() -> Bool {
        let isReturningFromAuthentication: Bool = self.isSceneTransitionFromAuthentication
        self.isSceneTransitionFromAuthentication = false
        self.isObscured = false
        self.refreshAvailableMethod()
        return isReturningFromAuthentication == false
    }

    private func authenticate(reason: String) async -> Bool {
        self.isAuthenticating = true
        defer {
            self.isAuthenticating = false
        }
        return await self.authenticator.authenticate(reason: reason) == .succeeded
    }
}
