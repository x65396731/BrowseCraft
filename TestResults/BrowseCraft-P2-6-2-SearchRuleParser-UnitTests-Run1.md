# BrowseCraft P2-6.2 SearchRule Parser Unit Tests Run 1

- Date: 2026-07-04
- Scope: P2-6.2 SearchRule parser entry and SearchRule `ExtractRule` field parsing.
- Destination: `platform=iOS Simulator,name=iPhone 17 Pro`
- Xcode: `/Applications/Xcode.app/Contents/Developer`

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SwiftSoupListParserTests
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests
```

## Result

- Targeted `SwiftSoupListParserTests`: passed, 3 tests in 1 suite, 0 failures.
- Full `BrowseCraftTests`: passed, 84 tests in 18 suites, 0 failures.

## Notes

- Targeted run confirmed `search-selector` was executed: 3 search candidates produced 2 valid preview items after skipping a result missing detail URL.
- Coverage includes SearchRule `item`, `fields.title`, `fields.detailURL`, relative URL resolution, `listOrder`, `ListContext` handoff, and content type inference from `listRuleRef`.

## xcresult

- Targeted run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-16-20-+0900.xcresult`
- Full run: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_01-16-37-+0900.xcresult`
