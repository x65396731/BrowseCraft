# Application Runtime

This directory is the App-side orchestration boundary for source runtimes.

Runtime contracts live in `BrowseCraftCore`, while concrete runtime wiring
stays in the App because it depends on App services such as repositories,
network loaders, parsers, cache storage, and view-facing domain models.

The architectural axis is `SourceDefinition + SourceRuntime`, not `SiteRule`.
`SiteRule` JSON is the configuration format for `RuleSourceRuntime` only. RSS and
video/plugin sources should be represented by their own runtime definitions
instead of being forced into the rule schema.

```text
SourceRuntime
  RuleSourceRuntime
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
- Keep `Rule/RuleSourceRuntime` as the rule-backed runtime implementation.
- Keep rule-only loading in `Rule/Loading/`; list/search/chapter/reader loaders
  are runtime internals, not shared App use cases.
- Keep rule-only mapping in `Rule/Mapping/RuleSourceRuntimeMapper`; it is not a
  shared App/Core compatibility layer.
- Keep `RSS/RSSSourceRuntime` as the RSS-backed runtime implementation for
  public feed list loading.
- Keep RSS mapping/loading in `RSS/Mapping/` and `RSS/Loading/`; RSS does not
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
  future plugin runtime can expose playback through the same boundary.
- Keep rule debug/source summary mapping in `Rule/Mapping/RuleSourceDebugMapping`.
- Add runtime-facing use cases before wiring Library and Reader features to them.
- Keep the plugin runtime slot explicit in the resolver/factory plan, while
  deferring plugin execution to a later phase.

Non-goals:

- Do not move SwiftSoup, WebView, Nuke, or network implementations into
  `BrowseCraftCore`.
- Do not treat `SiteRule` as the App-wide source axis. It is the configuration
  format used by `RuleSourceRuntime`.
- Do not add RSS, video, or plugin behavior as more `SiteRule` fields.
- Do not route RSS through `RuleSourceRuntime`; RSS uses `RSSSourceRuntime`.
- Do not route video through `RuleSourceRuntime`; video uses `VideoSourceRuntime`.
- Do not model every video skin or route variant as a top-level runtime kind.
  Keep MacCMS skins such as ewave/stui/myui/module-item inside the MacCMS
  adapter mapper as selector fallbacks.
- Do not put account login, CAPTCHA, JS signing, media decryption, or private
  site workflows into built-in video adapters. Those belong to plugin runtime
  planning.
- Do not execute plugin code until the plugin runtime phase explicitly starts.
