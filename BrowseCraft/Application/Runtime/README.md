# Application Runtime

This directory is the App-side orchestration boundary for source runtimes.

P3-7 keeps the runtime contract in `BrowseCraftCore`, while concrete runtime
wiring stays in the App because it depends on App services such as repositories,
network loaders, parsers, cache storage, and view-facing domain models.

The architectural axis is `SourceDefinition + SourceRuntime`, not `SiteRule`.
`SiteRule` JSON is the configuration format for `RuleSourceRuntime` only. RSS and
plugin sources should be represented by their own runtime definitions instead of
being forced into the rule schema.

```text
SourceRuntime
  RuleSourceRuntime
    config: SiteRule JSON
  RSSSourceRuntime
    config: RSS / Atom definition
  PluginSourceRuntime
    config: plugin manifest / package
```

Responsibilities:

- Resolve a `Source` through `SourceDefinition.runtimeKind` to the correct concrete runtime.
- Keep `SourceDefinitionMapping` as the runtime-neutral Source-to-Core metadata
  mapping boundary.
- Keep `Rule/RuleSourceRuntime` as the rule-backed runtime implementation.
- Keep rule-only loading in `Rule/Loading/`; list/search/chapter/reader loaders
  are runtime internals, not shared App use cases.
- Keep rule-only mapping in `Rule/Mapping/RuleSourceRuntimeMapping`; it is not a
  shared App/Core compatibility layer.
- Keep `RSS/RSSSourceRuntime` as the RSS-backed runtime implementation for
  public feed list loading.
- Keep RSS parsing/loading in `RSS/Parsing/` and `RSS/Loading/`; RSS does not
  extend `SiteRule` or the rule editor.
- Keep debug/source summary mapping in `Debug/RuleDebugSourceMapping`.
- Add runtime-facing use cases before wiring Library and Reader features to them.
- Keep the plugin runtime slot explicit in the resolver/factory plan, while
  deferring plugin execution to a later phase.

Non-goals:

- Do not move SwiftSoup, WebView, Nuke, or network implementations into
  `BrowseCraftCore`.
- Do not treat `SiteRule` as the App-wide source axis. It is the configuration
  format used by `RuleSourceRuntime`.
- Do not add RSS or plugin behavior as more `SiteRule` fields.
- Do not route RSS through `RuleSourceRuntime`; RSS uses `RSSSourceRuntime`.
- Do not execute plugin code until the plugin runtime phase explicitly starts.
