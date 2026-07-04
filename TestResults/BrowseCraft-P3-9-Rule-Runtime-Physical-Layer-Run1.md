# BrowseCraft P3-9 Rule Runtime Physical Layer - Run 1

- Date: 2026-07-05
- Scope: App-side `Application/Runtime/Rule` physical layer cleanup after P3-9 final re-freeze.
- Goal: Make the Rule runtime folder reflect the real runtime internals, separating loading and mapping instead of keeping every file flat under `Rule/`.

## Changes

- Moved rule runtime loading implementations into `BrowseCraft/Application/Runtime/Rule/Loading/`.
- Moved rule runtime mapping implementations into `BrowseCraft/Application/Runtime/Rule/Mapping/`.
- Split the previous combined reader loader file into:
  - `RuleSourceChapterLoader.swift`
  - `RuleSourceReaderLoader.swift`
- Updated `BrowseCraft/Application/Runtime/README.md` to describe:
  - `Rule/Loading/` as rule-only runtime loading internals.
  - `Rule/Mapping/` as rule-only runtime mapping internals.
- Kept `RuleSourceRuntime.swift` at the `Rule/` root as the runtime facade.

## Current Physical Structure

App Runtime:

```text
BrowseCraft/Application/Runtime/Debug/RuleDebugSourceMapping.swift
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceChapterLoader.swift
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceListLoader.swift
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceReaderLoader.swift
BrowseCraft/Application/Runtime/Rule/Loading/RuleSourceSearchLoader.swift
BrowseCraft/Application/Runtime/Rule/Mapping/RuleSourceItemReferenceMapping.swift
BrowseCraft/Application/Runtime/Rule/Mapping/RuleSourceRuntimeMapping.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntime.swift
BrowseCraft/Application/Runtime/SourceDefinitionMapping.swift
BrowseCraft/Application/Runtime/SourceRuntimeFactory.swift
BrowseCraft/Application/Runtime/SourceRuntimeResolver.swift
```

App Domain:

```text
BrowseCraft/Domain/CoreCompatibility/CoreResolvedRuleTypealiases.swift
BrowseCraft/Domain/CoreCompatibility/CoreRuleCandidateCompatibility.swift
BrowseCraft/Domain/CoreCompatibility/CoreRuleCandidateDraftApplierCompatibility.swift
BrowseCraft/Domain/CoreCompatibility/CoreRuleTypealiases.swift
BrowseCraft/Domain/Models/BuiltInSource.swift
BrowseCraft/Domain/Models/ChapterLink.swift
BrowseCraft/Domain/Models/ContentItem.swift
BrowseCraft/Domain/Models/ReaderChapter.swift
BrowseCraft/Domain/Models/ReadingHistory.swift
BrowseCraft/Domain/Models/RuleDebugModels.swift
BrowseCraft/Domain/Models/Source.swift
BrowseCraft/Domain/Models/SourceConfiguration.swift
BrowseCraft/Domain/Models/SourceType.swift
BrowseCraft/Domain/Repositories/ContentRepository.swift
BrowseCraft/Domain/Repositories/FavoriteRepository.swift
BrowseCraft/Domain/Repositories/HistoryRepository.swift
BrowseCraft/Domain/Repositories/SourceRepository.swift
BrowseCraft/Domain/Services/CookieHeaderResolver.swift
BrowseCraft/Domain/Services/HTTPClient.swift
BrowseCraft/Domain/Services/RenderedPageContentLoader.swift
BrowseCraft/Domain/Services/RuleCandidateAnalyzingService.swift
BrowseCraft/Domain/Services/RuleParsingService.swift
BrowseCraft/Domain/Services/URLResolvingService.swift
```

## Verification

Project generation:

```text
./scripts/regenerate-project.sh
```

Result:

- XcodeGen passed.
- CocoaPods integration restored with clean Ruby gem environment.

Targeted tests:

```text
xcodebuild test \
  -workspace BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath TestResults/P3-9-14-Rule-Runtime-Physical-Layer-Run2.xcresult \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests \
  -only-testing:BrowseCraftTests/RuleDebugSourceMappingTests
```

Result:

- 33 tests passed.
- 3 suites passed.
- 0 failures.

Note:

- Run 1 failed under the sandbox because `xcodebuild` could not access CoreSimulator and misreported the workspace; Run 2 was executed with simulator access and passed.

## Drift Check

Live App/Core source and tests contain no old transitional names:

```text
Bridge
Adapter
unsupportedPersistedSourceKind
RuleSourceRefreshUseCase
SearchSourceUseCase
RuleSourceReaderUseCases
RuleSourceReaderLoaders
WebViewContentLoader
webViewContentLoader
```

`git diff --check` passed.

Core repo status remained clean.

## Conclusion

This structure is closer to the intended architecture:

- `RuleSourceRuntime.swift` is the runtime facade.
- `Rule/Loading/` contains rule-only execution/loading internals.
- `Rule/Mapping/` contains rule-only mapping internals.
- Runtime-neutral files stay directly under `Application/Runtime`.
- The App/Core compatibility aliases stay in `Domain/CoreCompatibility`.

## Next Step

- Next subsection: no new P3-9 subsection is required unless another physical naming drift is found.
- Plan update needed: no, this is a post-freeze structural correction under the existing P3-9 architecture hygiene goal.
