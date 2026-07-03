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
        let latestBuiltInSources: [Source] = BuiltInSource.allBuiltIns()
        try self.updateExistingBuiltInSources(
            existingSources,
            latestBuiltInSources: latestBuiltInSources
        )

        let refreshedSources: [Source] = try self.sourceRepository.fetchSources()
        let existingIDs: Set<String> = Set(
            refreshedSources.map { source in
                return source.id
            }
        )

        for source: Source in latestBuiltInSources where existingIDs.contains(source.id) == false {
            try self.sourceRepository.saveSource(source)
        }
    }

    /// 中文注释：同步所有内置源。规则源在 BrowseCraftRulesKit，数据库只保存当前运行副本。
    private func updateExistingBuiltInSources(
        _ existingSources: [Source],
        latestBuiltInSources: [Source]
    ) throws {
        for existingSource: Source in existingSources {
            guard let latestBuiltInSource: Source = self.latestBuiltInSource(
                matching: existingSource,
                in: latestBuiltInSources
            ) else {
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
                "name=\(updatedSource.name) " +
                "chapterContainer=\(updatedSource.rule.primaryDetailRule?.chapterContainer ?? "nil") " +
                "chapterItem=\(updatedSource.rule.primaryDetailRule?.chapterItem ?? "nil")"
            )
            #endif
        }
    }

    private func latestBuiltInSource(
        matching existingSource: Source,
        in latestBuiltInSources: [Source]
    ) -> Source? {
        if let stableMatch: Source = latestBuiltInSources.first(where: { source in
            return source.id == existingSource.id
        }) {
            return stableMatch
        }

        let normalizedExistingName: String = self.normalizedName(existingSource.name)
        let normalizedExistingBaseURL: String = self.normalizedBaseURL(existingSource.baseURL)

        return latestBuiltInSources.first { source in
            return self.normalizedName(source.name) == normalizedExistingName
                && self.normalizedBaseURL(source.baseURL) == normalizedExistingBaseURL
        }
    }

    private func normalizedName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func normalizedBaseURL(_ baseURL: String) -> String {
        return baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
