import BrowseCraftCore
import Foundation

// 中文注释：RulePackageUseCases.swift 承载 P2-2 规则导入/导出的自有包格式与编解码边界。

/// 中文注释：导出结果同时携带包内容和建议文件名，UI 层只负责分享或保存。
struct RulePackageExport: Hashable {
    let packageJSON: String
    let suggestedFileName: String
}

/// 中文注释：导出当前 Source 的规则包；允许导出内置规则，但不会修改任何 Source。
struct ExportSourceRulePackageUseCase {
    private let sourceRepository: SourceRepository
    private let coder: RulePackageCoder
    private let appVersion: String?

    init(
        sourceRepository: SourceRepository,
        coder: RulePackageCoder = RulePackageCoder(),
        appVersion: String? = nil
    ) {
        self.sourceRepository = sourceRepository
        self.coder = coder
        self.appVersion = appVersion
    }

    func execute(sourceID: String) throws -> RulePackageExport {
        guard let source: Source = try self.sourceRepository.fetchSources().first(where: { source in
            return source.id == sourceID
        }) else {
            throw RulePackageError.sourceNotFound
        }

        return try self.execute(source: source)
    }

    func execute(source: Source) throws -> RulePackageExport {
        let packageJSON: String = try self.coder.encodePackage(
            rule: source.rule,
            sourceID: source.id,
            sourceName: source.name,
            sourceBaseURL: source.baseURL,
            appVersion: self.appVersion
        )

        return RulePackageExport(
            packageJSON: packageJSON,
            suggestedFileName: "\(self.sanitizedFileStem(for: source.name)).browsecraft-rule.json"
        )
    }

    private func sanitizedFileStem(for name: String) -> String {
        let allowedCharacters: CharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars: String.UnicodeScalarView = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
        var output: String = ""
        var previousWasSeparator: Bool = false

        for scalar: UnicodeScalar in scalars {
            if allowedCharacters.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if previousWasSeparator == false {
                output.append("-")
                previousWasSeparator = true
            }
        }

        let sanitized: String = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? "rule" : sanitized
    }
}

/// 中文注释：从规则包导入为用户 Source；不会覆盖本机已有 Source。
struct ImportSourceRulePackageUseCase {
    private let sourceRepository: SourceRepository
    private let coder: RulePackageCoder
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        sourceRepository: SourceRepository,
        coder: RulePackageCoder = RulePackageCoder(),
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.sourceRepository = sourceRepository
        self.coder = coder
        self.now = now
        self.idGenerator = idGenerator
    }

    func execute(packageJSON: String) throws -> Source {
        let package: BrowseCraftRulePackage = try self.coder.decodePackage(packageJSON: packageJSON)
        let existingSources: [Source] = try self.sourceRepository.fetchSources()
        let sourceID: String = self.importedSourceID(
            preferredID: package.metadata.sourceID,
            existingSources: existingSources
        )
        let now: Date = self.now()
        let source: Source = Source(
            id: sourceID,
            name: self.importedSourceName(package: package),
            baseURL: self.importedSourceBaseURL(package: package),
            type: .html,
            rule: package.rule,
            enabled: true,
            createdAt: now,
            updatedAt: now
        )

        try self.sourceRepository.saveSource(source)
        return source
    }

    private func importedSourceID(preferredID: String?, existingSources: [Source]) -> String {
        guard let preferredID: String = self.nonEmpty(preferredID),
              preferredID.hasPrefix("built-in.") == false,
              existingSources.contains(where: { source in source.id == preferredID }) == false else {
            return self.idGenerator()
        }

        return preferredID
    }

    private func importedSourceName(package: BrowseCraftRulePackage) -> String {
        return self.nonEmpty(package.metadata.sourceName) ?? package.rule.name
    }

    private func importedSourceBaseURL(package: BrowseCraftRulePackage) -> String {
        return self.nonEmpty(package.metadata.sourceBaseURL) ?? package.rule.baseUrl
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmedValue: String = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }
}
