# BrowseCraft P3-4.4 App Bridge Tests - Run 1

Date: 2026-07-04

## Scope

- `SourceDefinitionBridge`
- `SourceRuntimeInputBridge`
- `SourceRuntimeOutputBridge`
- P3-4 Core runtime contract regression
- BrowseCraft App unit regression suite

## Preparation

`project.yml` changed for the test target, so the project was regenerated before the App test run.

```bash
cd /Users/xiefei/Desktop/test-git
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
```

## Commands

```bash
cd /Users/xiefei/Desktop/BrowseCraftCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

```bash
cd /Users/xiefei/Desktop/test-git
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests
```

## Result

- BrowseCraftCore: passed.
  - 13 XCTest tests executed.
  - 0 failures.
- BrowseCraftTests first run: failed.
  - 106 tests in 21 suites executed.
  - 1 failure in `SourceRuntimeBridgeTests.sourceDefinitionBridgeMapsOwnershipRuleMetadataAndBaseURLFallback`.
  - Cause: `SourceDefinitionBridge` did not trim blank `baseURL`, so `URL(string: "   ")` became `%20%20%20` instead of falling back to `about:blank`.
- Fix applied:
  - `SourceDefinitionBridge.baseURL(from:)` now trims whitespace/newlines and falls back to `about:blank` for blank input.
- BrowseCraftTests rerun: passed.
  - 106 tests in 21 suites passed.
  - 0 failures.

## Notes

- `BrowseCraftCore` resolved as local package: `/Users/xiefei/Desktop/BrowseCraftCore`.
- `BrowseCraftRulesKit` resolved from `git@github.com:x65396731/BrowseCraftRulesKit.git @ main (cfcbd75)`.
- Passing App test `.xcresult` path:
  `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_08-38-47-+0900.xcresult`
- `.xcresult` remains a local ignored artifact; this Markdown file is the retained test summary.
