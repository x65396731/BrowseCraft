# BrowseCraft P3-9.7c RefreshSourceUseCase Boundary Narrowing - Run 1

Date: 2026-07-04

## Scope

- Apply P3-9.7b Path B.
- Move the real rule-backed list refresh implementation into `Application/Runtime/Rule`.
- Keep `Application/UseCases/RefreshSourceUseCase` as a thin App facade for `SourcesViewModel`.
- Make `RuleSourceRuntime` depend directly on a rule-prefixed internal refresh use case.

## Key Changes

- Added `BrowseCraft/Application/Runtime/Rule/RuleSourceRefreshUseCase.swift`.
- `RuleSourceRefreshUseCase` owns the rule-only refresh implementation:
  - reads `source.rule.availableListTabs`,
  - resolves rule list URL,
  - applies rule request config,
  - parses list HTML through `RuleParsingService`,
  - writes cache through `ContentRepository.replaceItems`.
- `RefreshSourceUseCase` is now a thin App facade that delegates to `RuleSourceRefreshUseCase`.
- `RuleSourceRuntime` now depends on `RuleSourceRefreshUseCase`.
- `SourceRuntimeFactory` now constructs `RuleSourceRefreshUseCase` for `RuleSourceRuntime`.
- Direct `RuleSourceRuntime` tests now pass `RuleSourceRefreshUseCase`; App facade tests still construct `RefreshSourceUseCase`.

## Project Generation

```sh
./scripts/regenerate-project.sh
```

Result:

- XcodeGen completed.
- CocoaPods integration was restored by the script.
- `BrowseCraft.xcodeproj/project.pbxproj`, `BrowseCraft.xcworkspace`, `Podfile.lock`, `Pods`, and `project.yml` did not appear as tracked changes after verification.

## Test Command

```sh
xcodebuild test \
  -workspace BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath TestResults/P3-9-7c-Run1.xcresult \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests
```

## Result

- Result: Passed
- Total tests: 28
- Passed: 28
- Failed: 0
- Result bundle: `TestResults/P3-9-7c-Run1.xcresult`

## Current Application Structure

```text
BrowseCraft/Application
BrowseCraft/Application/Runtime
BrowseCraft/Application/Runtime/Debug
BrowseCraft/Application/Runtime/Rule
BrowseCraft/Application/UseCases
```

## Current Rule Runtime Files

```text
BrowseCraft/Application/Runtime/Rule/RuleSourceItemReferenceMapping.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceReaderUseCases.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRefreshUseCase.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntime.swift
BrowseCraft/Application/Runtime/Rule/RuleSourceRuntimeMapping.swift
BrowseCraft/Application/Runtime/Rule/SearchSourceUseCase.swift
```

## Static Checks

- `Bridge|Adapter|unsupportedPersistedSourceKind`: no matches.
- `git diff --check`: passed.
- Core repository status: no App-driven changes expected.

## Next

- Next subsection: `P3-9.7d P3-9 final structure regression`.
- Plan update needed: no. P3-9.7c followed Path B from the existing plan.
