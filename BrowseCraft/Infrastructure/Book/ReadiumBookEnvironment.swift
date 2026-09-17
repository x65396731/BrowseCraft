import Foundation
// 中文注释：Readium 的 Publication / FormatSpecification 等类型尚未标注 Sendable，按前并发模块导入；
// 升级到标注了隔离的 Readium 版本后去掉 @preconcurrency 即可复查。
@preconcurrency import ReadiumShared
import ReadiumStreamer

// 中文注释：ReadiumBookEnvironment 是进程里唯一的一组 Readium 基础对象：HTTP 客户端、资产取回器与
// 出版物打开器。嗅探器、打开器、以后的阅读器都从这里拿，避免各建一份。Readium 3.x 的 Navigator 不再需要本地 HTTP 服务。

final class ReadiumBookEnvironment: @unchecked Sendable {
    static let shared: ReadiumBookEnvironment = ReadiumBookEnvironment()

    let httpClient: DefaultHTTPClient
    let assetRetriever: AssetRetriever
    let publicationOpener: PublicationOpener

    init() {
        let httpClient: DefaultHTTPClient = DefaultHTTPClient(configuration: .ephemeral)
        let assetRetriever: AssetRetriever = AssetRetriever(httpClient: httpClient)
        self.httpClient = httpClient
        self.assetRetriever = assetRetriever
        self.publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
    }

    /// 中文注释：Readium 认这些格式规格为音频（与 `AudioParser.audioSpecifications` 同一份清单）；zip / zab 音频包由嗅探器归为 `zab`。
    static let audioSpecifications: Set<FormatSpecification> = [
        .aac, .aiff, .flac, .mp4, .mp3, .ogg, .opus, .wav, .webm,
    ]

    static func localBookFormat(for format: Format) -> LocalBookFormat? {
        if format.conformsTo(.epub) {
            return .epub
        }
        if format.mediaType == .zab || format.conformsToAny(Self.audioSpecifications) {
            return .audiobook
        }
        return nil
    }
}
