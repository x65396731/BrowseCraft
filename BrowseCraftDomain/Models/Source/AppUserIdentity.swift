import Foundation

/// 中文注释：本地默认用户标识属于共享内核——Source 的默认 userID 需要它，
/// 而完整的 AppUser 实体（权益、StoreKit 摘要）留在 App 的 Domain 层。
public enum AppUserIdentity {
    public static let localDefaultID: String = "local.default"
}
