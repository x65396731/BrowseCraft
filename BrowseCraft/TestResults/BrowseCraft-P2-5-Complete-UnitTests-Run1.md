# BrowseCraft P2-5 Complete Unit Tests - Run 1

- Date: 2026-07-04
- Result: Passed after one compile fix
- Scope: P2-5 resolved graph migration targeted completeness test
- Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests \
  -only-testing:BrowseCraftTests/RequestConfigUseCaseTests \
  -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests \
  -only-testing:BrowseCraftTests/SwiftSoupReaderParserTests \
  -only-testing:BrowseCraftTests/RuleManagementUseCaseTests
```

## Summary

- Final run: 41 tests passed in 5 suites.
- Final failures: 0.
- `xcodebuild` result: `** TEST SUCCEEDED **`.

## First Run Note

- The first run failed at compile time before tests executed.
- Cause: `RuleDetailView.requestSection(rule:) -> some View` declared an opaque return type but had a local `let resolvedRule` before the `Section` expression, so Swift required an explicit return.
- Fix: changed the `Section("Request")` expression to `return Section("Request")`.

## Coverage Notes

- V2 `pages + ruleSets` detail/gallery resolution.
- Legacy rule fallback.
- Request priority.
- List context handoff into detail/reader.
- `treatDetailURLAsChapter` one-layer reader behavior.
- Previous RuleValidator / resolved graph crash path.
- P2-5.3 explicit parser rule handoff.
- P2-5.4 validator and read-only UI-adjacent resolved graph migration compiled successfully.

## Local Artifacts

- Failed first `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_00-09-09-+0900.xcresult`
- Passed final `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.04_00-09-36-+0900.xcresult`
- `.xcresult` bundles are not preserved in the repo.
