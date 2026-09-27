#if BROWSECRAFT_AD_TEST_TOOLS
import AdSupport
import AppTrackingTransparency
import Foundation

// 中文注释：只在 Debug / TestFlight 编入（project.yml `BROWSECRAFT_AD_TEST_TOOLS`）。
// AdMob 文档登记测试设备的正规做法之一：后台「设置 → 测试设备」填本机 IDFA。IDFA 要先经跟踪授权才读得到，
// 授权后广告 SDK 发请求时也带上同一个 IDFA，后台登记才对得上。正式版不申请授权、不含本文件。
enum AdTestDeviceTools {
    enum IDFAResult: Equatable {
        case available(String)
        case denied
        case trackingRestricted
    }

    @MainActor
    static func requestIDFA() async -> IDFAResult {
        let status: ATTrackingManager.AuthorizationStatus
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            status = await ATTrackingManager.requestTrackingAuthorization()
        } else {
            status = ATTrackingManager.trackingAuthorizationStatus
        }
        switch status {
        case .authorized:
            let idfa: String = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            if idfa == "00000000-0000-0000-0000-000000000000" {
                return .trackingRestricted
            }
            return .available(idfa)
        case .restricted:
            return .trackingRestricted
        default:
            return .denied
        }
    }
}
#endif
