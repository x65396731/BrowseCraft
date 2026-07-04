# BrowseCraft P3-8.9 Completeness Regression Run 1

- Date: 2026-07-04
- Scope: P3-8 runtime-first architecture completeness check before P3-9 RSSSourceRuntime.

## Commands

- Core:
  - `swift test`
  - Working directory: `/Users/xiefei/Desktop/BrowseCraftCore`
- App:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SourceRuntimeMappingTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -derivedDataPath /private/tmp/BrowseCraft-P3-8-9-Test-DerivedData -resultBundlePath /private/tmp/BrowseCraft-P3-8-9-Run1.xcresult`

## Results

- Core: passed.
  - Total: 38
  - Passed: 38
  - Failed: 0
- App: passed.
  - Total: 24
  - Passed: 24
  - Failed: 0
  - Result bundle: `/private/tmp/BrowseCraft-P3-8-9-Run1.xcresult`

## Architecture Closure

- Runtime axis is now `SourceDefinition + SourceRuntime`.
- `SiteRule` JSON is explicitly scoped to `RuleSourceRuntime` configuration.
- RSS and Plugin configurations can be represented as `SourceConfiguration` / `SourceDefinition` without placeholder `SiteRule` payloads.
- `SourceRuntimeResolver` dispatches by `SourceDefinition.kind`; legacy `SourceType` no longer decides runtime routing.
- Rule runtime naming has been cleaned up from `Adapter` to `RuleSourceRuntime`.
- App/Core handoff has a Core-owned `SourceItemReference` contract.
- Source persistence now has `kind + configJSON`; legacy `type + ruleJSON` stays readable during migration.

## Remaining Debt

- App-domain `Source` still carries `rule: SiteRule` as a migration compatibility field. This is acceptable for P3-8 because DB storage and runtime routing no longer require RSS/Plugin to be expressed as `SiteRule`.
- `LibraryViewModel` and `ReaderViewModel` still have rule-specific reads for tabs/request config/direct-reader behavior. This is already wrapped by runtime-facing list refresh for the current path; deeper UI/view-model rule dependency removal should be handled after RSS MVP proves the second runtime path.
- `SearchSourceUseCase` and `LoadReaderChapterUseCase` remain rule-specific old use cases inside `RuleSourceRuntime`. This is acceptable because they are rule runtime internals, not shared runtime architecture.
- RSS parsing, feed storage policy, account/cookie behavior, and Plugin execution remain non-goals for P3-8.

## Drift Check

- `git diff --check` passed.
- `git -C /Users/xiefei/Desktop/BrowseCraftCore diff --check` passed.
- `rg -n "Bridge|bridge|Adapter|RuleSourceRuntimeAdapter|runtimeAdapter|makeRuleSourceRuntimeAdapter" BrowseCraft BrowseCraftTests /Users/xiefei/Desktop/BrowseCraftCore/Sources /Users/xiefei/Desktop/BrowseCraftCore/Tests` returned no matches.
- No RSS/Plugin fields were added to `SiteRule`.
- No App-only dependencies were added to BrowseCraftCore.

## Current Physical Structure

```text
BrowseCraft/Application/Runtime
  Debug/RuleDebugSourceMapping.swift
  README.md
  Rule/RuleSourceItemReferenceMapping.swift
  Rule/RuleSourceRuntime.swift
  Rule/RuleSourceRuntimeMapping.swift
  SourceDefinitionMapping.swift
  SourceRuntimeFactory.swift
  SourceRuntimeResolver.swift

BrowseCraft/Domain/Models
  Source.swift
  SourceConfiguration.swift
  SourceType.swift
  SiteRule.swift

BrowseCraft/Infrastructure/Database
  AppDatabase.swift
  Records/SourceRecord.swift
  Repositories/GRDBSourceRepository.swift

/Users/xiefei/Desktop/BrowseCraftCore/Sources/BrowseCraftCore
  Rule/
  Runtime/
    SourceItemReference.swift
    SourceRuntime.swift
    SourceRuntimeError.swift
    SourceRuntimeModels.swift
  Source/
    ContentType.swift
    SourceDefinition.swift
```

## Conclusion

P3-8 is complete enough to enter P3-9 RSSSourceRuntime MVP. The remaining rule-specific reads are no longer RSS blockers as long as P3-9 keeps RSS inside its own runtime/config path and does not extend `SiteRule`.
