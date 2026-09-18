import ReadiumShared

// 中文注释：把 Infrastructure 的 Readium 实现挂到阅读器声明的协议上。装配根是唯一同时认识
// Features 与 Infrastructure 的层，因此这层符合性只能写在这里；阅读器因此不再直接引用 Infrastructure 类型。

extension ReadiumBookPublicationHandle: ReadiumPublicationProviding {}

struct ReadiumSitePublicationBuilderAdapter: SiteReadiumPublicationBuilding {
    private let builder: ReadiumSitePublicationBuilder

    init(builder: ReadiumSitePublicationBuilder = ReadiumSitePublicationBuilder()) {
        self.builder = builder
    }

    func build(
        manifest: BookPublicationManifest,
        contentProvider: @escaping BookChapterContentProvider
    ) -> Publication {
        return self.builder.build(manifest: manifest, contentProvider: contentProvider)
    }
}
