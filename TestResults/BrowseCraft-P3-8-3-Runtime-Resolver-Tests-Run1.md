# BrowseCraft P3-8.3 Runtime Resolver Tests Run 1

- Date: 2026-07-04
- Scope: P3-8.3 runtime registry/resolver boundary.
- Result: Passed.

## Changes Verified

- `SourceRuntimeResolver` now resolves through `SourceDefinition.kind`.
- Legacy `SourceType` is no longer the runtime selection axis.
- Rule-backed sources still resolve to the rule runtime.
- RSS and Plugin definitions have independent resolver branches and fail explicitly until their runtimes are connected in later phases.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SourceRuntimeMappingTests \
  -derivedDataPath /private/tmp/BrowseCraft-P3-8-3-Test-DerivedData \
  -resultBundlePath /private/tmp/BrowseCraft-P3-8-3-Run1.xcresult
```

```sh
xcrun xcresulttool get test-results summary \
  --path /private/tmp/BrowseCraft-P3-8-3-Run1.xcresult
```

```sh
git diff --check
```

## Result Summary

- Test bundle: `SourceRuntimeMappingTests`
- Total tests: 6
- Passed: 6
- Failed: 0
- Skipped: 0
- Result bundle: `/private/tmp/BrowseCraft-P3-8-3-Run1.xcresult`

## Notes

- `scripts/regenerate-project.sh` was not run for P3-8.3 because this node did not add, remove, or move Swift files.
- `scripts/regenerate-project.sh` had already been run for P3-8.2 when `SourceConfiguration.swift` and `SourceDefinitionMapping.swift` were added.
- No Core tests were run because P3-8.3 did not modify `/Users/xiefei/Desktop/BrowseCraftCore`.
