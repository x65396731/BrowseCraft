/// 中文注释：集中描述 Library 所拥有的内容消费页面装配入口。
/// Favorites 可以复用这些入口，但不拥有或复制 Comic、RSS、Video 的实现。
struct LibraryContentViewModelFactory {
    let makeComicDetail: (ContentItem, Source) -> ComicDetailViewModel
    let makeReader: (ContentItem, Source, ChapterLink?) -> ReaderViewModel
    let makeHistoryReader: (ComicChapterHistory, Source) -> ReaderViewModel
    let makeRSSDetail: (ContentItem, Source) -> RSSContentDetailViewModel
    let makeVideoDetail: (ContentItem, Source) -> VideoDetailViewModel
}
