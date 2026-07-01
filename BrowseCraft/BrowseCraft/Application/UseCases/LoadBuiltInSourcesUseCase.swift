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
        let existingIDs: Set<String> = Set(
            existingSources.map { source in
                return source.id
            }
        )

        if existingIDs.contains(BuiltInSource.myComicID) == false {
            let source: Source = BuiltInSource.myComic()
            try self.sourceRepository.saveSource(source)
        }

        try self.updateExistingMyComicSources(existingSources)
    }

    /// 中文注释：updateExistingMyComicSources 方法封装当前类型的一段业务或界面行为。
    private func updateExistingMyComicSources(_ existingSources: [Source]) throws {
        let latestBuiltInSource: Source = BuiltInSource.myComic()

        for existingSource: Source in existingSources {
            let normalizedName: String = existingSource.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isMyComicSource: Bool = normalizedName == "MYCOMIC"
                && existingSource.baseURL.contains("mycomic.com")

            if isMyComicSource == false {
                continue
            }

            if existingSource.rule == latestBuiltInSource.rule {
                continue
            }

            var updatedSource: Source = existingSource
            updatedSource.rule = latestBuiltInSource.rule
            updatedSource.updatedAt = Date()
            try self.sourceRepository.saveSource(updatedSource)
        }
    }
}
