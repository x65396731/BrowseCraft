# BrowseCraft P3-9.5 Rule-only Use Case Placement - Run 1

Date: 2026-07-04

## Scope

- Move rule-only source search and reader loading implementations into `Application/Runtime/Rule`.
- Keep Reader feature dependencies on App-level use case facades instead of depending directly on runtime internals.
- Split reader presentation request config resolution into a non-executing App use case.

## Key Changes

- `SearchSourceUseCase` now lives under `BrowseCraft/Application/Runtime/Rule/` as RuleSourceRuntime internal search execution.
- `RuleSourceLoadChaptersUseCase` and `RuleSourceLoadReaderChapterUseCase` now live in `BrowseCraft/Application/Runtime/Rule/RuleSourceReaderUseCases.swift`.
- `LoadChaptersUseCase` and `LoadReaderChapterUseCase` remain in `BrowseCraft/Application/UseCases/LoadReaderChapterUseCase.swift` as App-level facades for Reader feature callers.
- `ResolveReaderSourcePresentationUseCase` lives in `BrowseCraft/Application/UseCases/ResolveReaderSourcePresentationUseCase.swift` and only resolves display request config from optional rule configuration.
- `RefreshSourceUseCase` remains in App UseCases as a transitional entry point because `SourcesViewModel` still calls it directly.

## Project Generation

- Ran `./scripts/regenerate-project.sh` after moving Swift files.
- Ran `./scripts/regenerate-project.sh` again after restoring the App-level reader facade file.
- XcodeGen completed and CocoaPods integration was refreshed by the script.

## Test Command

```sh
xcodebuild test \
  -workspace BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath TestResults/P3-9-5-Run2.xcresult \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

## Result

- Result: Passed
- Total tests: 28
- Passed: 28
- Failed: 0
- Skipped: 0
- Result bundle: `TestResults/P3-9-5-Run2.xcresult`

## Notes

- The first Run1 result also passed before the final facade adjustment, but Run2 is the retained verification for the final P3-9.5 shape.
- This step intentionally does not remove `Source.rule` or route RSS/Plugin reader execution yet; that remains for later runtime work.
