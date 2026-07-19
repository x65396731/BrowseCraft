import Foundation

// 中文注释：漫画 API 请求会叠加站点/页面请求和 API 专属请求，避免固定头被局部 request 覆盖丢失。
enum ComicRuleAPIRequestResolver {
    static func request(
        base baseRequest: RequestConfig?,
        override overrideRequest: RequestConfig?,
        source: Source,
        item: ContentItem,
        page: Int? = nil,
        chapterURL: String? = nil
    ) -> RequestConfig? {
        guard let mergedRequest: RequestConfig = RequestConfigResolver().merged(
            base: baseRequest,
            override: overrideRequest
        ) else {
            return nil
        }

        return ComicRuleAPITemplateResolver.request(
            from: mergedRequest,
            source: source,
            item: item,
            chapterURL: chapterURL,
            page: page
        )
    }

}
