import BrowseCraftCore
import CryptoKit
import Foundation

// 中文注释：RulePackageUseCases.swift 承载 P2-2 规则导入/导出的自有包格式与编解码边界。

/// 中文注释：BrowseCraft 自有规则包 envelope；只描述可移植规则，不复用 Yealico 私有 QR 编码。
struct BrowseCraftRulePackage: Codable, Hashable {
    var formatVersion: Int
    var kind: String
    var metadata: RulePackageMetadata
    var rule: SiteRule
    var checksum: String
}

/// 中文注释：规则包元数据只放导入/导出辅助信息，真正执行仍以 `rule` 为准。
struct RulePackageMetadata: Codable, Hashable {
    var exportedAt: Date
    var sourceID: String?
    var sourceName: String
    var sourceBaseURL: String
    var ruleName: String
    var appVersion: String?
}

/// 中文注释：RulePackageCodec 负责将 SiteRule 包装成稳定 JSON，并在导入时校验 checksum。
struct RulePackageCodec {
    static let currentFormatVersion: Int = 1
    static let packageKind: String = "browsecraft.rule.package"

    private let jsonDecoder: JSONDecoder
    private let packageEncoder: JSONEncoder
    private let checksumEncoder: JSONEncoder
    private let now: () -> Date

    init(
        jsonDecoder: JSONDecoder = JSONDecoder(),
        now: @escaping () -> Date = Date.init
    ) {
        self.jsonDecoder = jsonDecoder
        self.packageEncoder = StableJSONCoding.makePrettyPrintedEncoder()
        self.checksumEncoder = StableJSONCoding.makeCanonicalEncoder()
        self.now = now
    }

    func encodePackage(
        rule: SiteRule,
        sourceID: String? = nil,
        sourceName: String? = nil,
        sourceBaseURL: String? = nil,
        appVersion: String? = nil
    ) throws -> String {
        let metadata: RulePackageMetadata = RulePackageMetadata(
            exportedAt: self.now(),
            sourceID: sourceID,
            sourceName: sourceName ?? rule.name,
            sourceBaseURL: sourceBaseURL ?? rule.baseUrl,
            ruleName: rule.name,
            appVersion: appVersion
        )

        let package: BrowseCraftRulePackage = BrowseCraftRulePackage(
            formatVersion: Self.currentFormatVersion,
            kind: Self.packageKind,
            metadata: metadata,
            rule: rule,
            checksum: try self.checksum(for: rule)
        )
        let data: Data = try self.packageEncoder.encode(package)

        guard let packageJSON: String = String(data: data, encoding: .utf8) else {
            throw RulePackageError.encodingFailed
        }

        return packageJSON
    }

    func decodePackage(packageJSON: String) throws -> BrowseCraftRulePackage {
        let data: Data = Data(packageJSON.utf8)
        let package: BrowseCraftRulePackage = try self.jsonDecoder.decode(BrowseCraftRulePackage.self, from: data)

        guard package.kind == Self.packageKind else {
            throw RulePackageError.unsupportedKind(package.kind)
        }

        guard package.formatVersion == Self.currentFormatVersion else {
            throw RulePackageError.unsupportedFormatVersion(package.formatVersion)
        }

        let expectedChecksum: String = try self.checksum(for: package.rule)
        guard package.checksum == expectedChecksum else {
            throw RulePackageError.checksumMismatch
        }

        return package
    }

    func checksum(for rule: SiteRule) throws -> String {
        let data: Data = try self.checksumEncoder.encode(rule)
        let digest: SHA256.Digest = SHA256.hash(data: data)
        let hex: String = digest.map { byte in
            return String(format: "%02x", byte)
        }
        .joined()
        return "sha256:\(hex)"
    }
}

/// 中文注释：导出结果同时携带包内容和建议文件名，UI 层只负责分享或保存。
struct RulePackageExport: Hashable {
    let packageJSON: String
    let suggestedFileName: String
}

/// 中文注释：导出当前 Source 的规则包；允许导出内置规则，但不会修改任何 Source。
struct ExportSourceRulePackageUseCase {
    private let sourceRepository: SourceRepository
    private let codec: RulePackageCodec
    private let appVersion: String?

    init(
        sourceRepository: SourceRepository,
        codec: RulePackageCodec = RulePackageCodec(),
        appVersion: String? = nil
    ) {
        self.sourceRepository = sourceRepository
        self.codec = codec
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
        let packageJSON: String = try self.codec.encodePackage(
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
    private let codec: RulePackageCodec
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        sourceRepository: SourceRepository,
        codec: RulePackageCodec = RulePackageCodec(),
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = {
            return UUID().uuidString
        }
    ) {
        self.sourceRepository = sourceRepository
        self.codec = codec
        self.now = now
        self.idGenerator = idGenerator
    }

    func execute(packageJSON: String) throws -> Source {
        let package: BrowseCraftRulePackage = try self.codec.decodePackage(packageJSON: packageJSON)
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

enum RulePackageError: LocalizedError, Equatable {
    case encodingFailed
    case unsupportedKind(String)
    case unsupportedFormatVersion(Int)
    case checksumMismatch
    case sourceNotFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Rule package could not be encoded as UTF-8 JSON."
        case .unsupportedKind(let kind):
            return "Unsupported rule package kind: \(kind)."
        case .unsupportedFormatVersion(let version):
            return "Unsupported rule package format version: \(version)."
        case .checksumMismatch:
            return "Rule package checksum does not match its rule content."
        case .sourceNotFound:
            return "Source was not found."
        }
    }
}
