import Foundation

// 中文注释：LoadBuiltInSourcesUseCase.swift 属于应用用例层，用于说明本文件承载的核心职责。

/// 中文注释：确保内置源规则存在于本地数据库中。
/// 中文注释：该用例不访问网络，只在缺失时写入内置 Source 记录。
struct LoadBuiltInSourcesUseCase {
    private let sourceRepository: SourceRepository

    init(sourceRepository: SourceRepository) {
        self.sourceRepository = sourceRepository
    }

    /// 中文注释：execute 方法封装当前类型的一段业务或界面行为。
    func execute() throws {
        let existingSources: [Source] = try self.sourceRepository.fetchSources()
        try self.updateExistingPrimaryBuiltInSources(existingSources)

        let refreshedSources: [Source] = try self.sourceRepository.fetchSources()
        let existingIDs: Set<String> = Set(
            refreshedSources.map { source in
                return source.id
            }
        )

        if existingIDs.contains(BuiltInSource.primaryBuiltInID) == false {
            let source: Source = BuiltInSource.primaryBuiltIn()
            try self.sourceRepository.saveSource(source)
        }
    }

    /// 中文注释：updateExistingPrimaryBuiltInSources 方法封装当前类型的一段业务或界面行为。
    private func updateExistingPrimaryBuiltInSources(_ existingSources: [Source]) throws {
        let latestBuiltInSource: Source = BuiltInSource.primaryBuiltIn()
        let latestName: String = latestBuiltInSource.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let latestBaseURL: String = latestBuiltInSource.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        for existingSource: Source in existingSources {
            let normalizedName: String = existingSource.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let normalizedBaseURL: String = existingSource.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let isStablePrimaryBuiltInSource: Bool = existingSource.id == BuiltInSource.primaryBuiltInID
            let isLegacyPrimaryBuiltInSource: Bool = normalizedName == latestName
                && normalizedBaseURL == latestBaseURL
            let isPrimaryBuiltInSource: Bool = isStablePrimaryBuiltInSource || isLegacyPrimaryBuiltInSource

            if isPrimaryBuiltInSource == false {
                continue
            }

            if existingSource.name == latestBuiltInSource.name
                && existingSource.baseURL == latestBuiltInSource.baseURL
                && existingSource.type == latestBuiltInSource.type
                && existingSource.rule == latestBuiltInSource.rule {
                continue
            }

            var updatedSource: Source = existingSource
            updatedSource.name = latestBuiltInSource.name
            updatedSource.baseURL = latestBuiltInSource.baseURL
            updatedSource.type = latestBuiltInSource.type
            updatedSource.rule = latestBuiltInSource.rule
            updatedSource.updatedAt = Date()
            try self.sourceRepository.saveSource(updatedSource)

            #if DEBUG
            print(
                "[BrowseCraftRule] Synced built-in source id=\(updatedSource.id) " +
                "chapterContainer=\(updatedSource.rule.detail?.chapterContainer ?? "nil") " +
                "chapterItem=\(updatedSource.rule.detail?.chapterItem ?? "nil")"
            )
            #endif
        }
    }
}
