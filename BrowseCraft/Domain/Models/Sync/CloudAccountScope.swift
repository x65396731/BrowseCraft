import Foundation

/// 中文注释：CloudAccountScope 是设备本地的数据空间标识，不是 Apple ID，也不上传到 CloudKit。
struct CloudAccountScope: RawRepresentable, Codable, Hashable, Sendable {
    static let localDefault: CloudAccountScope = CloudAccountScope(rawValue: "local.default")

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func cloud(hash: String) -> CloudAccountScope {
        return CloudAccountScope(rawValue: "cloud:\(hash)")
    }

    var isCloud: Bool {
        return self.rawValue.hasPrefix("cloud:")
    }
}
