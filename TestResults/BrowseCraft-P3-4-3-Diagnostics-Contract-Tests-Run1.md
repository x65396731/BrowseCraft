# BrowseCraft P3-4.3 Diagnostics Contract Tests - Run 1

Date: 2026-07-04

## Scope

- BrowseCraftCore runtime diagnostics contract changes.
- BrowseCraft App `RuleSourceRuntimeAdapter` diagnostics context bridge.
- Existing BrowseCraft unit regression suite.

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
  - New coverage includes `SourceRuntimeDiagnostics` context/candidate/export metadata Codable and Hashable behavior.
- BrowseCraftTests: passed.
  - 102 tests in 20 suites passed.
  - 0 failures.

## Notes

- `BrowseCraftCore` resolved as local package: `/Users/xiefei/Desktop/BrowseCraftCore`.
- `BrowseCraftRulesKit` resolved from `git@github.com:x65396731/BrowseCraftRulesKit.git @ main (cfcbd75)`.
- App test `.xcresult` path:
  `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dpkvwvzprjvrsuazgcmajvkpjgkg/Logs/Test/Test-BrowseCraft-2026.07.04_08-31-43-+0900.xcresult`
- `.xcresult` remains a local ignored artifact; this Markdown file is the retained test summary.
