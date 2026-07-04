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

Planned responsibilities:

- Resolve a `Source` to the correct concrete runtime.
- Keep `Rule/RuleSourceRuntimeAdapter` as the rule-backed runtime implementation.
- Keep rule-only mapping in `Rule/RuleSourceRuntimeMapping`; it is not a shared
  App/Core adapter layer.
- Keep debug/source summary mapping in `Debug/RuleDebugSourceMapping`.
- Add runtime-facing use cases before wiring Library and Reader features to them.
- Return unsupported diagnostics for RSS and plugin runtimes until those runtime
  implementations are introduced.
- Keep RSS and plugin runtime slots explicit in the resolver/factory plan, while
  deferring their implementation to later phases.

Non-goals:

- Do not move SwiftSoup, GRDB, WebView, Nuke, or network implementations into
  `BrowseCraftCore`.
- Do not treat `SiteRule` as the App-wide source axis. It is the configuration
  format used by `RuleSourceRuntimeAdapter`.
- Do not add RSS or plugin behavior as more `SiteRule` fields.
- Do not execute plugin code in P3-7.
