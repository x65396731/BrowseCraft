#if DEBUG
import BrowseCraftCore
import BrowseCraftDomain
import BrowseCraftRuntime
import Foundation

/// 中文注释：演示模式的 runtime 解析器。演示来源（`DemoContent.sites` 里的三个站）换成 `DemoSourceRuntime`，
/// 其它来源仍交给真实解析器，因此演示库里即使混进别的来源也照常执行。
struct DemoSourceRuntimeResolver: SourceRuntimeResolving {
    let base: any SourceRuntimeResolving

    func runtime(for source: Source) throws -> any SourceRuntime {
        let baseRuntime: any SourceRuntime = try self.base.runtime(for: source)
        guard let site: DemoSite = DemoContent.site(id: source.id) else {
            return baseRuntime
        }
        return DemoSourceRuntime(site: site, base: baseRuntime)
    }
}

/// 中文注释：`definition` 与 `capabilities` 沿用真实 runtime 按演示规则算出的结果，
/// 页面据此决定显示哪些入口；数据全部来自 `DemoContent`，不发任何请求。
struct DemoSourceRuntime: SourceSearchRuntime, SourceDetailRuntime, SourceReaderRuntime,
    SourceVideoPlaybackRuntime, SourceBookContentRuntime {
    let site: DemoSite
    let base: any SourceRuntime

    var definition: SourceDefinition {
        return self.base.definition
    }

    var capabilities: SourceRuntimeCapabilities {
        return self.base.capabilities
    }

    func loadList(_ input: SourceListInput) async throws -> SourceListOutput {
        return self.listOutput(works: DemoContent.listWorks(for: self.site), page: input.page)
    }

    func search(_ input: SourceSearchInput) async throws -> SourceListOutput {
        let keyword: String = input.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let works: [DemoWork] = DemoContent.listWorks(for: self.site).filter { work in
            return keyword.isEmpty || work.title.value.localizedCaseInsensitiveContains(keyword)
        }
        return self.listOutput(works: works, page: input.page)
    }

    func loadDetail(_ input: SourceDetailInput) async throws -> SourceDetailOutput {
        guard let work: DemoWork = DemoContent.work(site: self.site, detailURL: input.detailURL) else {
            throw SourceRuntimeError.invalidInput("Demo work not found: \(input.detailURL.absoluteString)")
        }
        let detailURL: URL = self.site.detailURL(for: work)
        let metadata: SourceDetailMetadata = SourceDetailMetadata(
            title: work.title.value,
            coverURL: work.coverURL,
            description: (work.synopsis ?? DemoContent.defaultSynopsis).value,
            attributes: self.site.kind == .video
                ? DemoContent.videoAttributes.map { attribute in
                    return SourceDetailAttribute(label: attribute.label.value, value: attribute.value.value)
                }
                : []
        )
        return SourceDetailOutput(
            metadata: metadata,
            chapters: self.chapters(detailURL: detailURL),
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    func loadBookContent(_ input: SourceBookContentInput) async throws -> SourceBookContentOutput {
        return SourceBookContentOutput(
            chapterURL: input.chapterURL,
            content: .text(
                title: nil,
                paragraphs: DemoContent.bookParagraphs.map(\.value)
            ),
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    /// 中文注释：漫画阅读与视频播放不在截图范围内，明确报不支持，页面按既有失败态显示。
    func loadReader(_ input: SourceReaderInput) async throws -> SourceReaderOutput {
        throw SourceRuntimeError.unsupported(.custom("Demo mode does not provide comic pages."))
    }

    func loadPlayback(_ input: SourceVideoPlaybackInput) async throws -> SourceVideoPlaybackOutput {
        throw SourceRuntimeError.unsupported(.custom("Demo mode does not provide video playback."))
    }

    private func listOutput(works: [DemoWork], page: Int) -> SourceListOutput {
        // 中文注释：只有一页，翻到第 2 页返回空列表，列表页就不会一直显示「载入更多」。
        let pageWorks: [DemoWork] = page <= 1 ? works : []
        let items: [SourceContentItem] = pageWorks.map { work in
            let detailURL: URL = self.site.detailURL(for: work)
            return SourceContentItem(
                id: detailURL.absoluteString,
                title: work.title.value,
                detailURL: detailURL,
                coverURL: work.coverURL,
                latestText: DemoContent.latestText(for: work.kind)
            )
        }
        return SourceListOutput(
            items: items,
            pagination: nil,
            diagnostics: SourceRuntimeDiagnostics.succeeded()
        )
    }

    private func chapters(detailURL: URL) -> [SourceChapter] {
        switch self.site.kind {
        case .video:
            return (1...12).map { number in
                return SourceChapter(
                    id: "episode-\(number)",
                    title: DemoContent.episodeTitle.formatted(number),
                    url: detailURL.appendingPathComponent("episode-\(number)")
                )
            }
        case .comic:
            return (1...48).reversed().map { number in
                return SourceChapter(
                    id: "chapter-\(number)",
                    title: DemoContent.comicChapterTitle.formatted(number),
                    url: detailURL.appendingPathComponent("chapter-\(number)"),
                    navigationOrder: .descending
                )
            }
        case .book:
            return (1...120).map { number in
                return SourceChapter(
                    id: "chapter-\(number)",
                    title: DemoContent.bookChapterTitle.formatted(number),
                    url: detailURL.appendingPathComponent("chapter-\(number)")
                )
            }
        }
    }
}
#endif
