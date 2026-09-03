import Foundation
import BrowseCraftDomain

// 中文注释：真实 catalog 数据仍由用户手动导入；这里仅升级已存在的 catalog 源定义。

/// 中文注释：不再在启动时自动写入任何 Source，用户初始状态保持空规则列表。
struct SyncBuiltInSourcesUseCase: Sendable {
    private let sourceRepository: SourceRepository
    private let catalogSources: [CatalogSource]
    private let catalogSourceMaterializer: CatalogSourceMaterializer
    private let now: @Sendable () -> Date

    init(
        sourceRepository: SourceRepository,
        catalogSources: [CatalogSource] = [],
        catalogSourceMaterializer: CatalogSourceMaterializer = CatalogSourceMaterializer(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sourceRepository = sourceRepository
        self.catalogSources = catalogSources
        self.catalogSourceMaterializer = catalogSourceMaterializer
        self.now = now
    }

    func execute() throws {
        let catalogSourcesByID: [String: CatalogSource] = Dictionary(
            uniqueKeysWithValues: self.catalogSources.map { source in
                return (source.id, source)
            }
        )
        let existingSources: [Source] = try self.sourceRepository.fetchSources()

        for existingSource: Source in existingSources {
            guard let catalogSource: CatalogSource = catalogSourcesByID[existingSource.id] else {
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
