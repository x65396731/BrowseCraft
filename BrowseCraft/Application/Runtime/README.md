# Application Runtime

This directory is the App-side orchestration boundary for source runtimes.

Runtime contracts live in `BrowseCraftCore`, while concrete runtime wiring
stays in the App because it depends on App services such as repositories,
network loaders, parsers, cache storage, and view-facing domain models.

The architectural axis is `SourceConfiguration + SourceRuntime`.
`SourceRuntimeFactory` dispatches directly to the matching domain factory;
`SourceDefinition` remains runtime-neutral metadata exposed to Core. Comics use
`SiteRule`; video uses the independent `VideoSiteRule` V2 contract. RSS and
plugin sources keep their own definitions.

Core protocols are capability-oriented. `SourceRuntime` is the shared list
entry; optional operations use `SourceSearchRuntime`, `SourceDetailRuntime`,
`SourceReaderRuntime`, `SourceDebugRuntime`, and `SourceVideoPlaybackRuntime`.
A concrete runtime must only adopt the operations it can execute instead of
implementing unrelated methods that always throw unsupported errors.

```text
SourceRuntime
  ComicSourceRuntime <- ComicSourceRuntimeFactory
    config: SiteRule JSON
  RSSSourceRuntime <- RSSSourceRuntimeFactory
    config: RSS / Atom definition
  VideoSourceRuntime <- VideoSourceRuntimeFactory
    config: VideoSiteRule V2
    list/detail/playback: explicit rule graph
    playback: native direct media or WebUI
  PluginSourceRuntime
    config: plugin manifest / package
```

Each domain root keeps only its runtime entry and factory. Supporting code is
grouped by responsibility:

```text
Comic/  API/ Loading/ Mapping/ Parsing/ Reader/
RSS/    Loading/ Mapping/ Parsing/
Video/  API/ Detection/ Loading/ Parsing/ Playback/ Rendering/
```

`Parsing/` contains App-side protocols and normalized parser results. Concrete
SwiftSoup adapters remain under `Infrastructure/Parsing/`; loaders and runtime
factories must depend on parsing protocols instead of importing SwiftSoup.

Naming follows the responsibility rather than the historical folder name:

- Runtime orchestration uses `ComicSource...`, `VideoSource...`, or `RSSSource...`
  (`SourceRuntime`, `SourceRuntimeFactory`, loaders, and output mappers).
- Pure rule-contract interpretation keeps `ComicRule...` or `VideoRule...`
  (`RuleAPITemplateResolver`, `RuleJSONResolver`, response evaluation,
  pagination resolution, and parsed rule values).
- `RuleSourceParsingService` names are explicit adapter-boundary protocols: they
  accept rule declarations but hide the concrete DOM parser from loading code.
- RSS transport/XML types use `RSSFeed...`; RSS is not a rule-backed source.

Video V2 keeps extraction, rendering, and playback policy separate:

```text
VideoSiteRule
  pages -> listRules -> detailRule -> playback
  static HTML or WebView-rendered DOM
  direct mp4/m3u8 -> Native
  explicit page/iframe fallback -> WebUI
```

P2-6 removed the V1 `MacCMS`/`GenericHTML` adapter graph. Video catalog items
must declare `version: 2` and pass `VideoSiteRuleValidator`; there is no adapter
inference or V1 fallback.

Responsibilities:

- Resolve a `Source` through `Source.configuration` to the correct concrete runtime.
- Keep `SourceRuntimeFactory` as both the sole dispatcher and the production
  implementation of `SourceRuntimeResolving`; do not add a second resolver layer.
- Keep `SourceDefinitionMapper` as the runtime-neutral Source-to-Core metadata
  mapping boundary.
- Keep `Runtime/Comic/ComicSourceRuntime` as the rule-backed runtime implementation.
- Keep comic API request/context replacement in `ComicRuleAPITemplateResolver`
  and JSON Path/value mapping in `ComicRuleJSONResolver`.
- Keep comic business-response evaluation in `ComicRuleAPIResponseEvaluator`.
  Its private legacy evaluator is the only missing-policy compatibility path;
  explicit policies never enter legacy evaluation.
- Keep rule-only loading in `Runtime/Comic/Loading/`; list/search/detail/reader loaders
  are runtime internals, not shared App use cases.
- Keep comic parsing contracts and normalized parser results in `Runtime/Comic/Parsing/`,
  behind `ComicRuleSourceParsingService`. The SwiftSoup
  adapter converts one DOM document into `ComicRuleParsedDetailMetadata + chapters`; the detail
  loader only orchestrates direct-chapter, DOM, and chapter-API selection. SwiftSoup types and
  selector mechanics must not leak into the loader or `SourceRuntime`.
- Normalize the parser output to Core `SourceDetailOutput` only in
  `ComicSourceRuntimeMapper`. `DetailChapterAPIRule.descriptionPath` is chapter subtitle
  semantics and must not be reused as a work-level detail description.
- Keep rule-only mapping in `Runtime/Comic/Mapping/ComicSourceRuntimeMapper`; it is not a
  shared App/Core compatibility layer.
- Use Core `SourceDetailOutput`, `SourceReaderOutput`, and `SourceRichContent` as the only
  cross-runtime detail/reader contracts. App `ContentItem`, `ChapterLink`, and `ReaderChapter`
  are UI/persistence projections created after the runtime boundary.
- Keep `RSS/RSSSourceRuntime` as the RSS-backed runtime implementation for
  feed list and article detail loading. RSS rich content must not be encoded into
  `SourceContentItem.latestText`; that field is a plain list summary.
- Keep RSS mapping/loading/parsing in `RSS/Mapping/`, `RSS/Loading/`, and `RSS/Parsing/`; RSS does not
  extend `SiteRule` or the rule editor.
- Keep `Video/VideoSourceRuntime` as the only video runtime implementation.
- Keep Video V2 request/context replacement in `VideoRuleAPITemplateResolver`,
  JSON Path/value/URL mapping in `VideoRuleJSONResolver`, and HTML parsing
  contracts in `Video/Parsing/`; none of these loading boundaries may import SwiftSoup.
- Keep video business-response evaluation in `VideoRuleAPIResponseEvaluator`.
  Video V2 always receives an explicit policy and has no legacy evaluator.
- Keep V2 list/detail/playback loading and parsing in `Video/`; selectors,
  iframe traversal, and fallback behavior come only from the resolved rule graph.
- Keep WebView/static HTML validation in `Video/Rendering/`; it is shared support
  for V2 loaders, not a source adapter.
- Keep playback request resolution in `Video/Playback/` and expose it through Core
  `SourceVideoPlaybackRuntime`, so a future plugin runtime can use the same boundary.
  Video detail uses Core `SourceDetailRuntime`; playback capability must not add a
  private detail API.
- Add runtime-facing use cases before wiring Library and Reader features to them.
- Keep the comic UI flow as `Library/Favorites -> ComicDetailView -> ReaderView`.
  `ComicDetailViewModel` consumes the complete `SourceDetailOutput`; `ReaderViewModel`
  starts only after a concrete chapter has been selected.
- Keep the plugin runtime slot explicit in the factory plan, while
  deferring plugin execution to a later phase.

## Comic Page Request Routing

Comic requests use one Core-owned inheritance path for DOM and API loading:

```text
SiteRule.sharedRequest
  -> PageRule.request / legacy list-detail-gallery request
  -> ListRule / DetailRule / GalleryRule request
  -> listAPI / chapterAPI / imageAPI request
```

Each child request overrides only the fields it declares unless its
`mergePolicy` is `override`. In particular, an explicit
`needsWebView: false` or `autoScroll: false` disables the shared value without
dropping shared headers, cookies, charset, or image configuration. This lets a
comic keep list and detail on HTTP while routing only the reader through
WebView. Loaders must consume `SiteRule.request(for:)` or `ResolvedSiteRule`
requests and must not read `sharedRequest` directly or add source-specific
route branches.

Native Reader images preserve the URL returned by the source because a signed
CDN URL can bind its signature to the original transport. ATS exceptions must
never use `NSAllowsArbitraryLoads`; when a legacy image CDN has no compatible
HTTPS resource route, use the narrowest verified exception domain in
`Info.plist`. Request logs record only the resource host/path and request shape,
never the signed query, Referer value, cookie, or token.

## Comic API Response Semantics Boundary

`responsePolicy` belongs to rule interpretation, not networking. It consumes an
already parsed JSON value and answers only whether field parsing may continue.
Comic and Video keep this logic in their domain-specific
`*RuleAPIResponseEvaluator.swift` files; the evaluator files must not import or
accept transport response types.

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
- Do not treat comic `SiteRule` as the App-wide source axis.
- Do not add RSS, `VideoSiteRule`, or plugin behavior as more comic `SiteRule` fields.
- Do not route RSS through `ComicSourceRuntime`; RSS uses `RSSSourceRuntime`.
- Do not route video through `ComicSourceRuntime`; video uses `VideoSourceRuntime`.
- Do not restore host/CMS inference, V1 adapters, or mapper fallbacks. Site
  differences belong in explicit V2 rules.
- Do not put account login, CAPTCHA, JS signing, media decryption, or private
  site workflows into implicit video logic. Those belong to explicit rule or
  plugin-runtime planning.
- Do not execute plugin code until the plugin runtime phase explicitly starts.
- Do not expand `responsePolicy` into an API-specific transport layer, response
  carrier, retry system, cancellation classifier, or fallback coordinator.
