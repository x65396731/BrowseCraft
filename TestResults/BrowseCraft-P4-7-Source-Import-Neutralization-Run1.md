# BrowseCraft P4.7 Source Import Neutralization Regression - Run 1

Date: 2026-07-05

## Scope

- P4.1-P4.6 architecture and naming review.
- Source import physical structure review.
- Rule-first UI wording regression review.
- P4 target unit tests.

## Static Checks

- `git diff --check`: passed.
- Main source list row wording adjusted from `Built-in rule` / `User rule` to `Built-in source` / `User source`.
- `Features/Sources/AddSourceView.swift` is now the neutral Add Source entry.
- `WebsiteRuleImportView.swift` and `WebsiteRulePackageImportView.swift` remain advanced website rule paths.
- `SourceImport*` models are grouped under `Domain/Models/Source/`.
- No new `Purpose` / `Feature` terminology was introduced.

## Tests

Command:

```sh
xcodebuild test \
  -workspace BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/BrowseCraftDerivedData-P4-7b \
  -resultBundlePath /private/tmp/BrowseCraft-P4-7-Run2.xcresult \
  -only-testing:BrowseCraftTests/SourceImportDraftTests \
  -only-testing:BrowseCraftTests/SourceImportRecommendationTests \
  -only-testing:BrowseCraftTests/SourceImportRecommendationUseCaseTests \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests
```

Result:

- Passed.
- Swift Testing: 22 tests passed, 0 failures.
- Result bundle: `/tmp/BrowseCraft-P4-7-Run2.xcresult`

## Notes

- Initial sandboxed `xcodebuild` run failed because CoreSimulatorService and Xcode log access were blocked. The target test run passed after running with elevated permissions.
- The first elevated run used an existing result bundle path and failed before testing; Run 2 used a fresh result bundle path and passed.
- Simulator emitted duplicate Objective-C class warnings from iOS 26.5 private frameworks; tests still passed.
