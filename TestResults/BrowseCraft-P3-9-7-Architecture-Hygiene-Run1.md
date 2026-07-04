# BrowseCraft P3-9.7 Architecture Hygiene - Run 1

Date: 2026-07-04

## Scope

- Finalize P3-9 architecture hygiene after Source Config Neutralization.
- Remove misleading physical structure leftovers.
- Narrow the `RefreshSourceUseCase` boundary so rule-only implementation is no longer presented as a shared App use case.
- Run final App and Core regression checks.

## Completed Subsections

### P3-9.7a Physical Structure Hygiene

- Confirmed `BrowseCraft/Application/Adapters/` was an empty directory.
- Removed the empty directory from the workspace.
- It was not tracked by git, so no tracked deletion was produced.

### P3-9.7b RefreshSourceUseCase Boundary Audit

- Audited call sites.
- Confirmed `RefreshSourceUseCase` was still rule-only despite its generic name.
- Chose Path B for P3-9.7c:
  - move real implementation into Rule runtime,
  - keep App facade for `SourcesViewModel`,
  - do not migrate `SourcesViewModel` to `RefreshSourceRuntimeUseCase` yet.

### P3-9.7c RefreshSourceUseCase Boundary Narrowing

- Added `BrowseCraft/Application/Runtime/Rule/RuleSourceRefreshUseCase.swift`.
- `RuleSourceRefreshUseCase` now owns the rule-backed list refresh implementation.
- `RefreshSourceUseCase` is now a thin App facade for `SourcesViewModel`.
- `RuleSourceRuntime` and `SourceRuntimeFactory` now depend on `RuleSourceRefreshUseCase`.
- Ran `./scripts/regenerate-project.sh`; XcodeGen and CocoaPods integration completed.
- Targeted App tests passed: 28 tests, 0 failures.

## Final Application Physical Structure

```text
BrowseCraft/Application
BrowseCraft/Application/Runtime
BrowseCraft/Application/Runtime/Debug
BrowseCraft/Application/Runtime/Rule
BrowseCraft/Application/UseCases
```

## Final Runtime / UseCase Files

```text
BrowseCraft/Application/Runtime/Debug/RuleDebugSourceMapping.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceItemReferenceMapping.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceReaderUseCases.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRefreshUseCase.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntime.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntimeMapping.swift
BrowseCraft/Application/Runtime/Rule/SearchSourceUseCase.swift
BrowseCraft/Application/Runtime/SourceDefinitionMapping.swift
BrowseCraft/Application/Runtime/SourceRuntimeFactory.swift
BrowseCraft/Application/Runtime/SourceRuntimeResolver.swift
BrowseCraft/Application/UseCases/AddSourceUseCase.swift
BrowseCraft/Application/UseCases/LoadBuiltInSourcesUseCase.swift
BrowseCraft/Application/UseCases/LoadHistoryUseCase.swift
BrowseCraft/Application/UseCases/LoadLibraryUseCase.swift
BrowseCraft/Application/UseCases/LoadReaderChapterUseCase.swift
BrowseCraft/Application/UseCases/LoadSourcesUseCase.swift
BrowseCraft/Application/UseCases/RecordOpenItemUseCase.swift
BrowseCraft/Application/UseCases/RefreshSourceRuntimeUseCase.swift
BrowseCraft/Application/UseCases/RefreshSourceUseCase.swift
BrowseCraft/Application/UseCases/ResolveReaderSourcePresentationUseCase.swift
BrowseCraft/Application/UseCases/RuleDebugUseCases.swift
BrowseCraft/Application/UseCases/RuleManagementUseCases.swift
BrowseCraft/Application/UseCases/RulePackageUseCases.swift
BrowseCraft/Application/UseCases/ToggleFavoriteUseCase.swift
```

## Boundary Conclusion

P3-9 is ready to freeze.

- `Source` is configuration-first.
- `SourceRecord` can restore `.rule`, `.rss`, and `.plugin` runtime-neutral sources.
- Library and Reader features no longer directly read `source.rule`.
- Rule-only list, search, chapters, and reader execution are under `Application/Runtime/Rule`.
- App-level use cases remain as feature-facing facades where needed.
- `Application/Adapters/` no longer exists.
- No Bridge / Adapter architecture naming remains.
- No RSS, plugin, or video fields were added to `SiteRule`.

Remaining accepted boundaries:

- Rule runtime internals still read `source.rule`.
- Rule debug / management / package workflows still read `source.rule`.
- Rule parser internals still read `source.rule`.
- Rule editor UI still reads `source.rule`.
- `SourcesViewModel` still calls `RefreshSourceUseCase` App facade; moving it to `RefreshSourceRuntimeUseCase` is deferred to a dedicated Sources runtimeization node.

## Static Checks

```sh
find BrowseCraft/Application -maxdepth 3 -type d | sort
rg -n "Bridge|Adapter|unsupportedPersistedSourceKind" BrowseCraft BrowseCraftTests /Users/xiefei/Desktop/BrowseCraftCore/Sources /Users/xiefei/Desktop/BrowseCraftCore/Tests
git diff --check
git status --short BrowseCraft.xcodeproj/project.pbxproj BrowseCraft.xcworkspace Podfile.lock Pods project.yml
git -C /Users/xiefei/Desktop/BrowseCraftCore status --short
```

## Static Check Result

- `Application` physical structure matches the intended P3-9 final shape.
- `Bridge|Adapter|unsupportedPersistedSourceKind`: no matches.
- `git diff --check`: passed.
- Generated project / workspace / Pods / Podfile.lock / project.yml: no tracked status changes.
- Core repository status: clean before final Core test.

## App Regression Command

```sh
xcodebuild test \
  -workspace BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath TestResults/P3-9-7d-Run1.xcresult \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/RuleManagementUseCaseTests \
  -only-testing:BrowseCraftTests/RulePackageUseCaseTests
```

## App Result

- Result: Passed
- Total tests: 38
- Passed: 38
- Failed: 0
- Result bundle: `TestResults/P3-9-7d-Run1.xcresult`

## Core Regression Command

```sh
swift test
```

Executed in:

```text
/Users/xiefei/Desktop/BrowseCraftCore
```

## Core Result

- Result: Passed
- XCTest tests: 38
- Failed: 0

## Next Recommendation

Freeze P3-9 after review.

Recommended next-stage priority:

1. `P3-10 PluginSourceRuntime MVP`
2. `RuleSourceRuntime video capability`
3. `RSS optional runtime`

Reasoning:

- Plugin runtime best matches the long-term goal of replacing hard dependencies for sites that need JavaScript signatures, dynamic tokens, or multiple API calls.
- Rule video capability is useful if the target site can be expressed by Yealico-style declarative rules.
- RSS is now a lower-priority optional runtime because it no longer carries the main architecture-validation burden.
