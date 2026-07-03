# BrowseCraft P2-6.6 Search Regression Unit Tests - Run 1

- Date: 2026-07-04
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Simulator: `iPhone 17 Pro`
- Scheme: `BrowseCraft`

## Targeted Regression

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/URLTemplateModelTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/SwiftSoupListParserTests \
  -only-testing:BrowseCraftTests/RuleDebugUseCaseTests
```

Result:

- Passed: 15 tests in 4 suites
- Failed: 0
- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-50-31-+0900.xcresult`

Notes:

- First targeted run exposed a test fixture issue: `urlPatterns.searchTemplate` takes priority over `SearchRule.url`, so the legacy fallback/page-placeholder assertions were not exercising the intended path.
- Fixed the test fixtures by clearing `searchTemplate` in those specific legacy SearchRule scenarios.
- Covered search URL encoding/raw keyword rendering, request priority, SearchRule parsing, nextPage link priority, page placeholder fallback, legacy SearchRule fallback, context handoff, SearchDebug session output, and search not mutating list cache.

## Full Unit Regression

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests
```

Result:

- Passed: 84 tests in 18 suites
- Failed: 0
- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-50-46-+0900.xcresult`

Environment note:

- `/Applications/Xcode-26.0.1.app/Contents/Developer` was not present on this Mac, so the run used the available `/Applications/Xcode.app/Contents/Developer`.
