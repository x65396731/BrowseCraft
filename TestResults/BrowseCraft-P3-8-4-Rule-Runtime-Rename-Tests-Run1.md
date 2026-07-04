# BrowseCraft P3-8.4 Rule Runtime Rename Tests Run 1

- Date: 2026-07-04
- Scope: P3-8.4 rule runtime naming cleanup.
- Result: Passed.

## Changes Verified

- `RuleSourceRuntimeAdapter.swift` was renamed to `RuleSourceRuntime.swift`.
- `RuleSourceRuntimeAdapter` type was renamed to `RuleSourceRuntime`.
- Factory and App container methods now use `makeRuleSourceRuntime`.
- Runtime tests and helpers now use `RuleSourceRuntime` naming.
- Current App/Test source no longer contains live `Bridge`, `Adapter`, or `RuleSourceRuntimeAdapter` references.

## Commands

```sh
./scripts/regenerate-project.sh
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -derivedDataPath /private/tmp/BrowseCraft-P3-8-4-Test-DerivedData \
  -resultBundlePath /private/tmp/BrowseCraft-P3-8-4-Run2.xcresult
```

```sh
git diff --check
```

```sh
rg -n "Bridge|bridge|Adapter|RuleSourceRuntimeAdapter|runtimeAdapter|makeRuleSourceRuntimeAdapter" BrowseCraft BrowseCraftTests
```

## Result Summary

- Test suites: `RequestConfigUseCaseTests`, `SourceRuntimeMappingTests`
- Total tests: 19
- Passed: 19
- Failed: 0
- Skipped: 0
- Result bundle: `/private/tmp/BrowseCraft-P3-8-4-Run2.xcresult`

## Notes

- The first sandboxed `xcodebuild` attempt failed before compilation because it could not access CoreSimulator services and user cache/log locations.
- The authorized rerun completed successfully.
- `./scripts/regenerate-project.sh` succeeded and restored CocoaPods integration after the Swift file rename.
- No Core tests were run because P3-8.4 did not modify `/Users/xiefei/Desktop/BrowseCraftCore`.
