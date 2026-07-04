# BrowseCraft P3-8.6 App Rule Dependency Audit

- Date: 2026-07-04
- Scope: App call-site audit before RSS work.
- Result: Audit complete.

## Goal

P3-8.6 checks whether App code is still treating `SiteRule` as the main source axis after P3-8.0~P3-8.5.

The expected architecture is:

- App source axis: `SourceDefinition + SourceRuntime`.
- Rule source config: `SiteRule`, only inside rule-backed source flows.
- RSS and Plugin: future runtime-specific config, not fields inside `SiteRule`.

## Command

```sh
rg -n "\b(SiteRule|ResolvedSiteRule|RuleResolver|ListTabRule|ListContext|RequestConfig|ListRule|DetailRule|GalleryRule|SearchRule|PageRule|RuleRefs)\b" \
  BrowseCraft/App BrowseCraft/Application BrowseCraft/Features BrowseCraft/Infrastructure BrowseCraft/Domain
```

## Allowed Rule Dependencies

These locations are expected to know rule schema details:

- Rule source editor and import flow:
  - `BrowseCraft/Features/Sources/AddSourceView.swift`
  - `BrowseCraft/Features/Sources/RuleBasicFieldsEditorView.swift`
  - `BrowseCraft/Features/Sources/RuleDetailView.swift`
  - `BrowseCraft/Features/Sources/RuleJSONEditorView.swift`
  - `BrowseCraft/Features/Sources/SourcesViewModel.swift`
  - `BrowseCraft/Application/UseCases/AddSourceUseCase.swift`
  - `BrowseCraft/Application/UseCases/RuleManagementUseCases.swift`
  - `BrowseCraft/Application/UseCases/RulePackageUseCases.swift`

- Rule debug and candidate analysis:
  - `BrowseCraft/Application/UseCases/RuleDebugUseCases.swift`
  - `BrowseCraft/Domain/Models/RuleDebugModels.swift`
  - `BrowseCraft/Domain/Services/RuleCandidateAnalyzingService.swift`
  - `BrowseCraft/Domain/Services/RuleCandidateDraftApplier.swift`
  - `BrowseCraft/Infrastructure/Parsing/SwiftSoupRuleCandidateAnalyzer.swift`

- Rule parsing and rule-backed runtime:
  - `BrowseCraft/Domain/Services/RuleParsingService.swift`
  - `BrowseCraft/Infrastructure/Parsing/SwiftSoupRuleParser.swift`
  - `BrowseCraft/Application/Runtime/Rule/RuleSourceRuntime.swift`
  - `BrowseCraft/Application/Runtime/Rule/RuleSourceRuntimeMapping.swift`
  - `BrowseCraft/Application/Runtime/Rule/RuleSourceItemReferenceMapping.swift`

These are rule-specific surfaces, so keeping `SiteRule`, `ListRule`, `DetailRule`, `GalleryRule`, `SearchRule`, `PageRule`, `RuleRefs`, and `RequestConfig` here is acceptable.

## Needs Continued Narrowing

### Library ViewModel still reads rule schema

`BrowseCraft/Features/Library/LibraryViewModel.swift` still reaches into rule-specific state:

- `imageRequestConfig(for:)` reads `source.rule.request(for: self.selectedListTab)` around line 186.
- `shouldOpenReaderDirectly(for:)` resolves `source.rule` around line 206.
- `listTabs` exposes `selectedSource?.rule.availableListTabs` around line 210.
- `listContext(from:)` builds rule-derived `ListContext` around line 296.

Current status:

- Acceptable during P3-8 because Library tabs are still rule-backed.
- Not acceptable as a long-term RSS/Plugin-neutral ViewModel shape.

Recommended next direction:

- Move tab presentation and direct-reader intent behind a runtime/source presentation helper.
- Keep `ListContext` as a runtime context key, but avoid ViewModel deriving it directly from `ListTabRule`.

### Reader ViewModels still resolve rule requests

`BrowseCraft/Features/Reader/ReaderViewModel.swift` still reads rule request config:

- `readerImageRequestConfig` resolves `source.rule` around line 100.
- `detailCoverRequestConfig` resolves `source.rule` around line 208.

Current status:

- Acceptable for rule-backed image request behavior.
- Should be moved behind `SourceItemReference` / runtime output context or a rule runtime presentation helper before RSS reader UI work.

Recommended next direction:

- Reader should receive display-safe request metadata from runtime/handoff context.
- Reader UI should not call `RuleResolver` directly.

### Search use case remains rule-specific

`BrowseCraft/Application/UseCases/SearchSourceUseCase.swift` still chooses `SearchRule` and `PageRule` directly:

- request/context construction around lines 81-88.
- `searchRuleEntry(source:)` uses `source.rule.ruleSets` and `source.rule.pages` around lines 151-176.
- URL override path mutates a temporary rule source around lines 195-203.

Current status:

- Acceptable while only rule search exists.
- Should become `RuleSourceRuntime`-owned or split behind runtime search before RSS search/feed discovery.

### Detail/Reader use cases are rule runtime candidates

`BrowseCraft/Application/UseCases/LoadReaderChapterUseCase.swift` remains rule-specific:

- `LoadChaptersUseCase.execute` resolves `source.rule` around line 58.
- direct-reader decision uses `ResolvedSiteRule` around lines 74-90.
- `LoadReaderChapterUseCase.execute` resolves `source.rule` around line 174.
- reader parsing uses `GalleryRule` around lines 215-228.

Current status:

- This logic is already wrapped by `RuleSourceRuntime`.
- The old direct use cases remain App main-flow dependencies and should eventually become rule runtime internals or be called only through runtime-facing use cases.

### Source persistence is still rule-only

`BrowseCraft/Infrastructure/Database/Records/SourceRecord.swift` still persists:

- `type` at line 14.
- `ruleJSON` at line 15.
- `init(source:)` encodes `source.rule` at lines 20-27.
- `domainModel()` decodes `SiteRule` at lines 34-43.

Current status:

- This is the largest RSS-blocking persistence debt.
- P3-8.1/8.2 introduced `SourceConfiguration` and `SourceDefinitionMapper`, but DB has not migrated to `kind + configJSON`.

Recommended next direction:

- A later P3-8 storage node should add phased `kind + configJSON` support while keeping legacy `ruleJSON` readable.

## Acceptable Infrastructure Rule Dependencies

The following are implementation details and can remain rule-aware for now:

- `AlamofireHTTPClient`, `WKWebViewHTMLLoader`, `DefaultPageContentLoader`, and `HTTPClient` accept `RequestConfig`.
- `GRDBContentRepository` and `ContentItemRecord` persist `ListContext` as list cache identity.
- `CookieHeaderResolver` interprets `RequestConfig.cookiePolicy`.
- `URLResolvingService` still builds URLs from `ListRule` and `SearchRule`.

These dependencies are not source-axis decisions by themselves. They become a problem only if RSS/Plugin are forced to produce fake `SiteRule` to use them.

## Drift Check

- No new `Bridge` or `Adapter` layer is present.
- `Application/Adapters` is currently an empty directory.
- P3-8.5 added `SourceItemReference` in Core and `RuleSourceItemReferenceMapper` in App runtime rule scope.
- No RSS/Plugin behavior was added to `SiteRule`.
- Core still has no App-only dependency.
- UI/ViewModel did not gain new rule schema dependencies in this audit node.

## P3-8.6 Conclusion

The architecture is improved but not fully RSS-ready.

Closed before this audit:

- Runtime resolver now uses `SourceDefinition.kind`.
- Rule runtime naming no longer uses `Adapter`.
- Core has a neutral `SourceItemReference` handoff model.
- App rule runtime has a local handoff mapper.

Still before RSS:

- DB source persistence must stop being rule-only.
- Library ViewModel should stop deriving tabs/direct-reader behavior directly from `SiteRule`.
- Reader ViewModel should stop resolving rule request config directly.
- Search/detail/reader old use cases should continue moving behind runtime-facing boundaries.

## Verification

No build or test was run for P3-8.6 because this node is audit/documentation only.
