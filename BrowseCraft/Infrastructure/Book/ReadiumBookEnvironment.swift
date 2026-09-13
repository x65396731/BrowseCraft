import Foundation
import ReadiumAdapterGCDWebServer
import ReadiumShared
import ReadiumStreamer

// 中文注释：ReadiumBookEnvironment 是进程里唯一的一组 Readium 基础对象：HTTP 客户端、资产取回器、
// 出版物打开器与给 EPUB Navigator 用的本地 HTTP 服务。嗅探器、打开器、以后的阅读器都从这里拿，避免各建一份。

final class ReadiumBookEnvironment: @unchecked Sendable {
    static let shared: ReadiumBookEnvironment = ReadiumBookEnvironment()

    let httpClient: DefaultHTTPClient
    let assetRetriever: AssetRetriever
    let publicationOpener: PublicationOpener
    /// 中文注释：EPUB Navigator 需要的本地服务；懒建，只有真正打开 EPUB 阅读器时才起端口。
    private(set) lazy var httpServer: GCDHTTPServer = GCDHTTPServer(assetRetriever: self.assetRetriever)

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
