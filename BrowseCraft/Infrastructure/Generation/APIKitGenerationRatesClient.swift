import BrowseCraftAPIKit
import Foundation

/// `GenerationRatesFetching` 的 PortalCore 适配器（Campaign-And-Rate-Notices-Design.md 第三节）。
///
/// 中文注释：`scope` 未知的那一档当作取不到（nil）——服务端先于 App 加取值时界面只是少显示一档，不解码失败。
struct APIKitGenerationRatesClient: GenerationRatesFetching {
    private let api: PortalGenerationRatesAPI

    init(api: PortalGenerationRatesAPI) {
        self.api = api
    }

    func fetchRates(kind: RuleGenerationSourceKind) async throws -> GenerationRates {
        let response: PortalGenerationRatesResponse = try await self.api.fetchRates(
            kind: Self.portalSourceKind(kind)
        )
        return GenerationRates(
            region: response.region,
            windowDays: response.windowDays,
            normal: Self.tierRate(response.rates.normal),
            hard: Self.tierRate(response.rates.hard)
        )
    }

    private static func tierRate(_ rate: PortalGenerationTierRate?) -> GenerationTierRate? {
        guard let rate: PortalGenerationTierRate else {
            return nil
        }
        let scope: GenerationRateScope
        switch rate.scope {
        case "region":
            scope = .region
        case "global":
            scope = .global
        default:
            return nil
        }
        return GenerationTierRate(
            rate: rate.rate,
            samples: rate.samples ?? 0,
            successes: rate.successes ?? 0,
            scope: scope
        )
    }

    /// 中文注释：App 与 APIKit 各有一份 kind 枚举，`switch` 保证任一边新增取值时编译期报错。
    private static func portalSourceKind(
        _ kind: RuleGenerationSourceKind
    ) -> PortalRuleGenerationSourceKind {
        switch kind {
        case .video:
            return .video
        case .comic:
            return .comic
        case .book:
            return .book
        }
    }
}
