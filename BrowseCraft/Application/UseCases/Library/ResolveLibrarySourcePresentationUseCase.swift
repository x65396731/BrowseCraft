import Foundation

// 中文注释：ResolveLibrarySourcePresentationUseCase 是 Library 展示层边界，不执行 rule runtime。
struct ResolveLibrarySourcePresentationUseCase {
    func listTabs(for source: Source?) -> [ListTabRule] {
        guard let source: Source = source else {
            return []
        }

        if case .video(let configuration) = source.configuration {
            return self.videoListTabs(for: configuration)
        }

        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return []
        }

        return rule.availableListTabs
    }

    func imageRequestConfig(for source: Source, listTab: ListTabRule?) -> RequestConfig? {
        if case .video(let configuration) = source.configuration {
            return self.videoImageRequestConfig(for: configuration)
        }

        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return nil
        }

        return rule.request(for: listTab)
    }

    private func videoImageRequestConfig(for configuration: VideoSourceConfiguration) -> RequestConfig? {
        return self.merged(
            base: configuration.definition.sharedRequest,
            override: configuration.definition.listRequest
        )
    }

    private func merged(base: RequestConfig?, override: RequestConfig?) -> RequestConfig? {
        guard let override: RequestConfig else {
            return base
        }

        guard let base: RequestConfig else {
            return override
        }

        if override.mergePolicy == .override {
            return override
        }

        var headers: [String: String] = base.headers ?? [:]
        override.headers?.forEach { key, value in
            headers[key] = value
        }

        var imageHeaders: [String: String] = base.imageHeaders ?? [:]
        override.imageHeaders?.forEach { key, value in
            imageHeaders[key] = value
        }

        let imageRequest: ImageRequestConfig? = self.mergedImageRequest(
            base: base.imageRequest,
            override: override.imageRequest
        )

        return RequestConfig(
            scope: override.scope ?? base.scope,
            mergePolicy: override.mergePolicy ?? base.mergePolicy,
            method: override.method ?? base.method,
            headers: headers.isEmpty ? nil : headers,
            body: override.body ?? base.body,
            cookiePolicy: override.cookiePolicy ?? base.cookiePolicy,
            cookiePriority: override.cookiePriority ?? base.cookiePriority,
            cookieScope: override.cookieScope ?? base.cookieScope,
            charset: override.charset ?? base.charset,
            needsWebView: override.needsWebView ?? base.needsWebView,
            autoScroll: override.autoScroll ?? base.autoScroll,
            imageHeaders: imageHeaders.isEmpty ? nil : imageHeaders,
            imageRequest: imageRequest
        )
    }

    private func mergedImageRequest(
        base: ImageRequestConfig?,
        override: ImageRequestConfig?
    ) -> ImageRequestConfig? {
        guard let override: ImageRequestConfig else {
            return base
        }

        guard let base: ImageRequestConfig else {
            return override
        }

        if override.mergePolicy == .override {
            return override
        }

        var headers: [String: String] = base.headers ?? [:]
        override.headers?.forEach { key, value in
            headers[key] = value
        }

        return ImageRequestConfig(
            headers: headers.isEmpty ? nil : headers,
            cookiePolicy: override.cookiePolicy ?? base.cookiePolicy,
            cookiePriority: override.cookiePriority ?? base.cookiePriority,
            cookieScope: override.cookieScope ?? base.cookieScope,
            mergePolicy: override.mergePolicy ?? base.mergePolicy
        )
    }

    private func videoListTabs(for configuration: VideoSourceConfiguration) -> [ListTabRule] {
        let tabs: [VideoSourceListTab]
        if configuration.listTabs.isEmpty {
            tabs = [
                VideoSourceListTab(
                    id: "video.home",
                    title: "首页",
                    url: configuration.definition.entryURL.absoluteString
                )
            ]
        } else {
            tabs = configuration.listTabs
        }

        return tabs.map { tab in
            return self.videoListTab(tab)
        }
    }

    private func videoListTab(_ tab: VideoSourceListTab) -> ListTabRule {
        return ListTabRule(
            id: tab.id,
            title: tab.title,
            list: ListRule(
                id: tab.id,
                url: tab.url,
                item: tab.itemSelector ?? "",
                title: tab.titleSelector ?? "",
                link: tab.linkSelector ?? "",
                cover: tab.coverSelector,
                type: .video,
                latestText: tab.latestTextSelector
            ),
            context: ListContext(
                pageId: "video",
                tabId: tab.id,
                sectionId: nil,
                listRuleId: tab.id,
                sectionRole: tab.role
            )
        )
    }

    func shouldOpenReaderDirectly(for source: Source) -> Bool {
        guard let rule: SiteRule = source.ruleConfiguration?.rule else {
            return false
        }

        return RuleResolver().resolve(rule).treatsDetailURLAsChapter
    }

    func listContext(from listTab: ListTabRule?) -> ListContext? {
        guard let listTab: ListTabRule = listTab else {
            return nil
        }

        if var context: ListContext = listTab.context {
            if context.listRuleId == nil {
                context.listRuleId = listTab.list.id
            }

            return context
        }

        return ListContext(
            pageId: listTab.id,
            tabId: listTab.id,
            sectionId: nil,
            listRuleId: listTab.list.id,
            sectionRole: .main
        )
    }
}
