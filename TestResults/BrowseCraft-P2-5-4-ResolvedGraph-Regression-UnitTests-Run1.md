# BrowseCraft P2-5.4 Resolved Graph Regression Unit Tests - Run 1

- Date: 2026-07-03
- Result: Passed
- Scope: targeted BrowseCraft unit tests for P2-5 resolved graph migration
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

- 41 tests passed in 5 suites.
- 0 failures.
- `xcodebuild` result: `** TEST SUCCEEDED **`.

## Coverage Notes

- V2 `pages + ruleSets` detail/gallery resolution covered by `SiteRuleV2CompletenessTests`, `SwiftSoupDetailParserTests`, and `SwiftSoupReaderParserTests`.
- Legacy resolved graph fallback covered by `resolvedRuleFallsBackToLegacyDetailAndGalleryRules`.
- Request priority covered by `v2RequestsResolveByRulePageAndSharedPriority` and `RequestConfigUseCaseTests`.
- Context handoff covered by detail/reader request use case tests and parser context scope tests.
- Previous validator crash path covered by `RuleManagementUseCaseTests.validatorAcceptsCompleteV2Rule`.
- P2-5.3 explicit parser rule handoff covered by `parsedDetailRuleIDs == ["detail"]` and `parsedGalleryRuleIDs == ["reader-gallery"]`.

## Local Artifacts

- `.xcresult`: `/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.03_23-55-44-+0900.xcresult`
- The `.xcresult` bundle is not preserved in the repo.
