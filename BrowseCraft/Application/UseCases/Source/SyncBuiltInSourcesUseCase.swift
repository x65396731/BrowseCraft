import Foundation
import BrowseCraftRulesKit

// 中文注释：真实 catalog 数据仍由用户手动导入；这里仅升级已存在的 catalog 源定义。

/// 中文注释：不再在启动时自动写入任何 Source，用户初始状态保持空规则列表。
struct SyncBuiltInSourcesUseCase {
    private let sourceRepository: SourceRepository
    private let catalogSources: [BrowseCraftCatalogSource]
    private let catalogSourceMaterializer: CatalogSourceMaterializer
    private let now: () -> Date

    init(
        sourceRepository: SourceRepository,
        catalogSources: [BrowseCraftCatalogSource] = [],
        catalogSourceMaterializer: CatalogSourceMaterializer = CatalogSourceMaterializer(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sourceRepository = sourceRepository
        self.catalogSources = catalogSources
        self.catalogSourceMaterializer = catalogSourceMaterializer
        self.now = now
    }

    func execute() throws {
        let catalogSourcesByID: [String: BrowseCraftCatalogSource] = Dictionary(
            uniqueKeysWithValues: self.catalogSources.map { source in
                return (source.id, source)
            }
        )
        let existingSources: [Source] = try self.sourceRepository.fetchSources()

        for existingSource: Source in existingSources {
            guard let catalogSource: BrowseCraftCatalogSource = catalogSourcesByID[existingSource.id] else {
                continue
            }

            let updatedSource: Source = try self.catalogSourceMaterializer.source(
                from: catalogSource,
                createdAt: existingSource.createdAt,
                updatedAt: self.now(),
                enabled: existingSource.enabled
            )
            if updatedSource != existingSource {
                try self.sourceRepository.saveSource(updatedSource)
            }
        }
    }
}
