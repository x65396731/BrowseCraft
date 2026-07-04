# BrowseCraft P3-8.0 Architecture Audit

Date: 2026-07-04

## Scope

P3-8.0 freezes the architecture target before RSS work starts. This node is an audit/planning step only.

No production code was changed. No build or test was run.

## Target

The source architecture must be runtime-first:

- App axis: `SourceDefinition + SourceRuntime`
- Rule runtime config: `SiteRule` JSON
- RSS runtime config: RSS/Atom definition
- Plugin runtime config: plugin manifest/package

RSS work must not require adding RSS fields to `SiteRule`, expanding `RuleSourceRuntimeAdapter`, or making UI/ViewModel logic inspect rule schema.

## Current Structure

```text
BrowseCraft/Application/
  Adapters/
  Runtime/
    Debug/
      RuleDebugSourceMapping.swift
    Rule/
      RuleSourceRuntimeAdapter.swift
      RuleSourceRuntimeMapping.swift
    README.md
    SourceRuntimeFactory.swift
    SourceRuntimeResolver.swift
  UseCases/
    RefreshSourceRuntimeUseCase.swift
    RefreshSourceUseCase.swift
    LoadReaderChapterUseCase.swift
    ...
```

```text
/Users/xiefei/Desktop/BrowseCraftCore/Sources/BrowseCraftCore/
  Diagnostics/
  Runtime/
    SourceRuntime.swift
    SourceRuntimeError.swift
    SourceRuntimeModels.swift
  Source/
    ContentType.swift
    SourceDefinition.swift
  Rule/
    SiteRule.swift
    ResolvedSiteRule.swift
    RuleValidator.swift
    RulePackageCodec.swift
    SourceRulePrimitives.swift
    Candidate/
      SourceRuleCandidateModels.swift
      SourceRuleCandidateDraftApplier.swift
  Serialization/
    StableJSONCoding.swift
```

## Audit Findings

### RSS-blocking items

1. `Source` is still rule-bound.
   - Current state: `Source` has `var rule: SiteRule`.
   - Current DB state: `SourceRecord` persists `ruleJSON`.
   - Impact: RSS/plugin cannot become first-class source configs until source persistence has a neutral config boundary.
   - Next step: P3-8.1 must pick the source config shape before RSS starts.

2. Resolver still uses legacy `SourceType`.
   - Current state: `.html`, `.json`, and `.xml` all route to rule runtime; `.rss` throws unsupported.
   - Impact: this keeps runtime selection coupled to old source type labels instead of `SourceDefinition.kind` or a registry.
   - Next step: P3-8.3 must move resolver/factory toward runtime kind or definition kind.

3. `RuleSourceRuntimeAdapter` still carries Adapter naming.
   - Current state: file/type/factory/tests use `RuleSourceRuntimeAdapter`.
   - Impact: behavior is in the right physical layer, but the name still reads as a bridge/adapter boundary.
   - Next step: P3-8.4 should rename it to `RuleSourceRuntime` or equivalent.

4. Detail/Reader runtime inputs are too thin.
   - Current state: `loadDetail` and `loadReader` synthesize a minimal `ContentItem` from a URL.
   - Lost semantics: original item id/title/type/latestText/list context/direct-reader intent/request intent.
   - Impact: RSS/plugin would inherit the same handoff weakness if implemented now.
   - Next step: P3-8.5 must design `SourceItemReference` or an equivalent richer input model.

### RSS-nonblocking but should be tracked

1. Library list refresh already has a runtime-facing use case.
   - `LibraryViewModel` uses `RefreshSourceRuntimeUseCase`.
   - The rule runtime still writes through existing `RefreshSourceUseCase`, then Library reloads cache by context.
   - This is acceptable for P3-8 and should be preserved.

2. Rule schema remains visible in rule-specific areas.
   - Rule editor, parser, rule debug, rule package import/export, and rule runtime internals still use `SiteRule`.
   - This is acceptable. The boundary problem is App-wide source persistence and generic runtime selection, not rule-specific features.

3. Core physical layer is aligned enough for P3-8.
   - `Source`, `Runtime`, `Rule`, `Diagnostics`, and `Serialization` are separated.
   - Empty `Models/` may remain on disk but is not a tracked architecture layer.

## Frozen P3-8 Order

1. P3-8.1: Source persistence neutral design.
2. P3-8.2: SourceDefinition storage/mapping boundary.
3. P3-8.3: Runtime registry/resolver design and first implementation.
4. P3-8.4: Rename rule runtime away from Adapter semantics.
5. P3-8.5: Detail/Reader handoff model.
6. P3-8.6: UI/ViewModel/use case rule dependency audit.
7. P3-8.7: Architecture guardrail tests.
8. P3-8.8: Completeness regression and transition to P3-9 RSS.

## Non-goals

- Do not implement RSS parser in P3-8.0.
- Do not add RSS/plugin fields to `SiteRule`.
- Do not move SwiftSoup, GRDB, Nuke, HTTP/WebView, AppContainer, or ViewModels into BrowseCraftCore.
- Do not remove rule editor access to `SiteRule`.
- Do not replace Reader/Detail main UI chain before the handoff model is designed.

## Verification

No tests were run. P3-8.0 is a planning/audit node and does not change production code.

