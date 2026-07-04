# BrowseCraft P3-6 UI/ViewModel Runtime Regression Tests - Run 1

Date: 2026-07-04

## Scope

- P3-6.1 through P3-6.4 UI/ViewModel dependency narrowing regression check.
- Covered Library tab presentation state, Library request/direct-reader presentation boundary, Reader detail cover request presentation, and the list runtime adapter pilot path.
- Added runtime adapter list test coverage before running the regression suite.

## Test Code Added

Added `ruleSourceRuntimeAdapterLoadListUsesRuntimeContextTab` in `RequestConfigUseCaseTests`.

Coverage:

- `RuleSourceRuntimeAdapter.loadList` selects the tab from `SourceRuntimeContext.tabID`.
- The selected tab's list rule and request config are used for the list request.
- Tab-specific request headers are passed to the HTTP client.
- Returned content keeps list context metadata from the selected tab/list rule.
- Runtime diagnostics report a succeeded status.

## Environment

- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Xcode version: 26.6 Build 17F113

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Working directory:

```text
/Users/xiefei/BrowseCraftCore
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -derivedDataPath /private/tmp/BrowseCraft-P3-6-Test-DerivedData -resultBundlePath /private/tmp/BrowseCraft-P3-6-App.xcresult
```

Working directory:

```text
/Users/xiefei/BrowseCraft
```

## Results

- `BrowseCraftCore swift test`: passed, 34 tests, 0 failures.
- `BrowseCraftTests`: passed, 102 tests in 22 suites, 0 failures.

## Notes

- The App test run includes the new P3-6.4 runtime adapter list path test.
- The App test run emitted the existing Swift Testing macro note around `#expect(true)` in a success-path guard; it did not fail the run.
- `.xcresult` path: `/private/tmp/BrowseCraft-P3-6-App.xcresult`
- DerivedData path: `/private/tmp/BrowseCraft-P3-6-Test-DerivedData`
