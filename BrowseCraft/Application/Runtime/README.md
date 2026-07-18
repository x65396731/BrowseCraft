# Application Runtime

This directory is the App-side orchestration boundary for source runtimes.

Runtime contracts live in `BrowseCraftCore`, while concrete runtime wiring
stays in the App because it depends on App services such as repositories,
network loaders, parsers, cache storage, and view-facing domain models.

The architectural axis is `SourceDefinition + SourceRuntime`, not `SiteRule`.
`SiteRule` JSON is the configuration format for `ComicRuleSourceRuntime` only. RSS and
video/plugin sources should be represented by their own runtime definitions
instead of being forced into the rule schema.

```text
SourceRuntime
  ComicRuleSourceRuntime
    config: SiteRule JSON
  RSSSourceRuntime
    config: RSS / Atom definition
  VideoSourceRuntime
    config: VideoSourceDefinition
    content mapping:
      macCMS
      genericHTML
    rendering:
      staticHTML
      webView
    playback candidate:
      directMedia
      iframePlayer
  PluginSourceRuntime
    config: plugin manifest / package
```

Video runtime keeps four axes separate:

```text
ContentMapping
  macCMS
  genericHTML

Rendering
  static HTML
  WebView-rendered DOM

PlaybackCandidate
  direct mp4/m3u8
  iframePlayer/pageOnly

Escape
  plugin
```

`macCMS` and `genericHTML` are built-in content mappers. WebView is an HTML
acquisition/rendering mode, not a mapper. `iframePlayer` is a playback
candidate, not a list/detail adapter. `plugin` is the escape hatch for
account-bound, encrypted, signed, or site-specific workflows that should not
expand the built-in content mapper layer.

Video playback also has a narrower playback layer:

```text
Video/PlaybackCandidate
  IframePlayerCandidateResolver
  VideoIframePlayerResolver
```

`IframePlayerCandidateResolver` does not make iframe pages natively playable. It
normalizes iframe/embed playback candidates into
`SourceVideoMediaKind.iframePlayer + SourceVideoPlaybackStatus.pageOnly`, preserving a
clear handoff point for later WebView, plugin, or media URL extraction work.
`VideoIframePlayerResolver` can then follow iframe-player playback candidates
inside the playback layer. It is not a content frame/site shell resolver.

Responsibilities:

- Resolve a `Source` through `SourceDefinition.runtimeKind` to the correct concrete runtime.
- Keep `SourceDefinitionMapping` as the runtime-neutral Source-to-Core metadata
  mapping boundary.
- Keep `Runtime/ComicRule/ComicRuleSourceRuntime` as the rule-backed runtime implementation.
- Keep rule-only loading in `Runtime/ComicRule/Loading/`; list/search/detail/reader loaders
  are runtime internals, not shared App use cases.
- Keep comic detail parsing behind `ComicRuleSourceParsingService.parseDetail`. The SwiftSoup
  adapter converts one DOM document into `ComicRuleParsedDetailMetadata + chapters`; the detail
  loader only orchestrates direct-chapter, DOM, and chapter-API selection. SwiftSoup types and
  selector mechanics must not leak into the loader or `SourceRuntime`.
- Normalize the parser output to Core `SourceDetailOutput` only in
  `ComicRuleSourceRuntimeMapper`. `DetailChapterAPIRule.descriptionPath` is chapter subtitle
  semantics and must not be reused as a work-level detail description.
- Keep rule-only mapping in `Runtime/ComicRule/Mapping/ComicRuleSourceRuntimeMapper`; it is not a
  shared App/Core compatibility layer.
- Use Core `SourceDetailOutput`, `SourceReaderOutput`, and `SourceRichContent` as the only
  cross-runtime detail/reader contracts. App `ContentItem`, `ChapterLink`, and `ReaderChapter`
  are UI/persistence projections created after the runtime boundary.
- Keep `RSS/RSSSourceRuntime` as the RSS-backed runtime implementation for
  feed list and article detail loading. RSS rich content must not be encoded into
  `SourceContentItem.latestText`; that field is a plain list summary.
- Keep RSS mapping/loading/parsing in `RSS/Mapping/`, `RSS/Loading/`, and `RSS/Parsing/`; RSS does not
  extend `SiteRule` or the rule editor.
- Keep `Video/VideoSourceRuntime` as the video-backed runtime implementation.
- Keep video list/detail/playback loading in `Video/Loading/`; those loaders
  call a `VideoContentMapper` after static or rendered HTML is available.
- Keep built-in video content mapping in `Video/ContentMapping/`; `MacCMSVideoContentMapper`
  and `GenericHTMLVideoContentMapper` describe content structure, not WebView or plugin execution.
- Keep WebView/static HTML requirements in `Video/Rendering/`; WebView is an HTML
  acquisition mode, not a content adapter.
- Keep iframe/embed playback handling in `Video/PlaybackCandidate/`; iframePlayer
  is a playback candidate, not a list/detail content adapter.
- Keep `VideoPlaybackRuntimeCapability` as the video playback capability so a
  future plugin runtime can expose playback through the same boundary. Video detail
  always uses `SourceRuntime.loadDetail`; playback capability must not add a private detail API.
- Add runtime-facing use cases before wiring Library and Reader features to them.
- Keep the comic UI flow as `Library/Favorites -> ComicDetailView -> ReaderView`.
  `ComicDetailViewModel` consumes the complete `SourceDetailOutput`; `ReaderViewModel`
  starts only after a concrete chapter has been selected.
- Keep the plugin runtime slot explicit in the resolver/factory plan, while
  deferring plugin execution to a later phase.

## Comic API Response Semantics Boundary

`responsePolicy` belongs to rule interpretation, not networking. It consumes an
already parsed JSON value and answers only whether field parsing may continue.

```text
existing page/API loading
  -> existing JSON parsing
  -> explicit responsePolicy OR isolated legacy evaluation
  -> itemPath
  -> field mapping
```

The boundary is fixed as follows:

- `envelope` evaluates only the declared business-status path, success values,
  failure paths, and message paths.
- `transportOnly` skips business-envelope evaluation. It does not change HTTP,
  retry, cancellation, WebView, or fallback behavior.
- A missing `responsePolicy` is the only path into the isolated legacy
  `code=0` plus `errors/error` compatibility evaluator. Explicit policies never
  fall through to legacy; endpoints whose success value is `200` must declare it.
- The evaluator must not receive an HTTP response object or know about status
  codes, headers, final URLs, request sending, retries, cancellation, DOM, or
  API-to-DOM fallback.
- `itemPath` state and field mapping happen after response semantics. A real
  empty array is a parsing result; a non-empty input that maps to no output is a
  response-contract error.
- `pipelineOnly` may block DOM fallback at the reader entry point, but it must
  not introduce a separate network or composite-error architecture.

This contract intentionally keeps site-specific success values in rules while
leaving the App's existing transport implementation unchanged.

Non-goals:

- Do not move SwiftSoup, WebView, Nuke, or network implementations into
  `BrowseCraftCore`.
- Do not treat `SiteRule` as the App-wide source axis. It is the configuration
  format used by `ComicRuleSourceRuntime`.
- Do not add RSS, video, or plugin behavior as more `SiteRule` fields.
- Do not route RSS through `ComicRuleSourceRuntime`; RSS uses `RSSSourceRuntime`.
- Do not route video through `ComicRuleSourceRuntime`; video uses `VideoSourceRuntime`.
- Do not model every video skin or route variant as a top-level runtime kind.
  Keep MacCMS skins such as ewave/stui/myui/module-item inside the MacCMS
  adapter mapper as selector fallbacks.
- Do not put account login, CAPTCHA, JS signing, media decryption, or private
  site workflows into built-in video adapters. Those belong to plugin runtime
  planning.
- Do not execute plugin code until the plugin runtime phase explicitly starts.
- Do not expand `responsePolicy` into an API-specific transport layer, response
  carrier, retry system, cancellation classifier, or fallback coordinator.
