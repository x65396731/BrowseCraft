import Foundation

/// 成功率按哪一级统计（Campaign-And-Rate-Notices-Design.md 第三节）：本地区，或样本不足时退回的全部地区。
enum GenerationRateScope: Hashable, Sendable {
    case region
    case global
}

/// 一档的生成成功率。`rate` 为 nil 表示全部地区样本也不足，这一档不显示。
struct GenerationTierRate: Hashable, Sendable {
    let rate: Double?
    let scope: GenerationRateScope
}

/// 网址输入页「取页方式」组里成功率一行的数据（`GET /v1/generation-rates`）。
///
/// 中文注释：只活在一次网址输入 sheet 的状态里，不落库、不缓存。`region` 是服务端按请求 IP 判断的两位国家码，
/// 判断不出时为 nil；本地化成地区名是界面层的事。
struct GenerationRates: Hashable, Sendable {
    let region: String?
    let windowDays: Int
    let normal: GenerationTierRate?
    let hard: GenerationTierRate?

    func rate(for tier: GenerationAcquisitionTier) -> GenerationTierRate? {
        switch tier {
        case .normal:
            return self.normal
        case .hard:
            return self.hard
        }
    }
}

/// 读取生成成功率的 Application 端口。不要登录；失败由调用方吞掉并记日志，界面不显示这一行。
protocol GenerationRatesFetching: Sendable {
    func fetchRates(kind: RuleGenerationSourceKind) async throws -> GenerationRates
}
