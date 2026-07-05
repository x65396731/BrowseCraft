import Foundation

// 中文注释：ImageCacheSettings 集中定义图片缓存档位、持久化 key 和自动清理目标。

/// 中文注释：图片缓存上限只允许产品确认过的固定档位，避免 Settings 中出现任意 MB 裸数。
enum ImageCacheLimitOption: Int, CaseIterable, Hashable, Identifiable {
    case megabytes512 = 512
    case gigabytes1 = 1024
    case gigabytes2 = 2048

    var id: Int {
        return self.rawValue
    }

    var megabytes: Int {
        return self.rawValue
    }

    var bytes: Int {
        return self.megabytes * 1024 * 1024
    }

    var displayTitle: String {
        switch self {
        case .megabytes512:
            return "512 MB"
        case .gigabytes1:
            return "1 GB"
        case .gigabytes2:
            return "2 GB"
        }
    }

    init?(megabytes: Int) {
        self.init(rawValue: megabytes)
    }
}

struct ImageCacheSettings: Equatable {
    static let userDefaultsKey: String = "settings.imageCacheLimit"
    static let defaultLimit: ImageCacheLimitOption = .megabytes512
    /// 中文注释：主动清理目标低于上限，避免缓存刚被清到临界值后又频繁触发下一次清理。
    static let trimTargetRatio: Double = 0.75
    static let availableLimits: [ImageCacheLimitOption] = ImageCacheLimitOption.allCases

    var limit: ImageCacheLimitOption

    init(limit: ImageCacheLimitOption = Self.defaultLimit) {
        self.limit = limit
    }

    var limitBytes: Int {
        return self.limit.bytes
    }

    /// 中文注释：Nuke 原生 trimRatio 不是 public；这里保存 BrowseCraft 自己执行 LRU 清理时的目标容量。
    var trimTargetBytes: Int {
        return Int(Double(self.limitBytes) * Self.trimTargetRatio)
    }

    var displayTitle: String {
        return self.limit.displayTitle
    }

    static func load(from userDefaults: UserDefaults = .standard) -> ImageCacheSettings {
        let storedMegabytes: Int = userDefaults.integer(forKey: Self.userDefaultsKey)
        let limit: ImageCacheLimitOption = ImageCacheLimitOption(megabytes: storedMegabytes) ?? Self.defaultLimit
        return ImageCacheSettings(limit: limit)
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(self.limit.megabytes, forKey: Self.userDefaultsKey)
    }
}
