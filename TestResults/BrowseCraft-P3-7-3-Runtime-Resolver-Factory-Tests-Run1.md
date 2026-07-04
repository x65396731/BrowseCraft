# BrowseCraft P3-7.3 Runtime Resolver Factory Tests - Run 1

Date: 2026-07-04

## Scope

- P3-7.1 runtime physical directory landing.
- P3-7.2 `SourceRuntimeResolver`.
- P3-7.3 `SourceRuntimeFactory` and `AppContainer` runtime factory delegation.

## Environment

- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Xcode version: 26.6 Build 17F113

## Preparation

New Swift files were added under the XcodeGen-managed source tree, so the project was regenerated before testing:

```sh
scripts/regenerate-project.sh
```

This ran `xcodegen generate` and `env -u GEM_HOME -u GEM_PATH pod install`.

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SourceRuntimeBridgeTests -derivedDataPath /private/tmp/BrowseCraft-P3-7-3-Test-DerivedData -resultBundlePath /private/tmp/BrowseCraft-P3-7-3-App-Run2.xcresult
```

Working directory:

```text
/Users/xiefei/BrowseCraft
```

## Results

- `SourceRuntimeBridgeTests`: passed, 6 tests in 1 suite, 0 failures.
- The two new P3-7 resolver tests passed:
  - `sourceRuntimeResolverReturnsRuleRuntimeForRuleBackedSourceTypes`
  - `sourceRuntimeResolverRejectsRSSUntilRuntimeIsConnected`

## Notes

- The first non-escalated test attempt failed before running tests because the sandbox could not access CoreSimulator services. The escalated rerun passed.
- The original result bundle path already existed on the rerun, so the successful run used `/private/tmp/BrowseCraft-P3-7-3-App-Run2.xcresult`.
- DerivedData path: `/private/tmp/BrowseCraft-P3-7-3-Test-DerivedData`
