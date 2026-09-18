@preconcurrency import ReadiumShared

// 中文注释：阅读器需要一个 Readium `Publication`，但它的来源在 Infrastructure（本地书打开器、站点书装配器）。
// 三层约束同时成立：Features 不得直接引用 Infrastructure 类型；Application 与 Shared 都不允许认识
// Application 之上的东西或 Readium（Application 明确禁止 import Readium，Shared 不得引用 Application 类型）。
// 因此这两个能力由 Features 自己声明，符合性在装配根 `App/Composition` 上挂给 Infrastructure 的实现。
// （2026-09-18 收敛边界豁免时引入。）

/// 中文注释：已打开的出版物句柄能交出 Readium 的 `Publication`。
/// 本地书走 `BookPublicationOpening` 端口返回句柄，阅读器只按本协议取用，不认识具体句柄类型。
protocol ReadiumPublicationProviding {
    var publication: Publication { get }
}

/// 中文注释：把站点书的 manifest 与按需取正文的 provider 装配成 Readium `Publication`。
protocol SiteReadiumPublicationBuilding: Sendable {
    func build(
        manifest: BookPublicationManifest,
        contentProvider: @escaping BookChapterContentProvider
    ) -> Publication
}
