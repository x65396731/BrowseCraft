# BrowseCraft P1-5 Complete Unit Tests Run 1

- 中文注释：本次测试用于验证 P1-5 全环节链路，从 TabGroup/Page/Section/ListContext 到 Detail/Reader context scope。
- Date: 2026-07-03
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -only-testing:BrowseCraftTests/SwiftSoupListParserTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests -only-testing:BrowseCraftTests/SwiftSoupReaderParserTests test
```

## Result

- Status: Passed
- Executed: 28 tests / 5 suites
- Coverage:
  - `SiteRuleV2CompletenessTests`
  - `SwiftSoupListParserTests`
  - `RequestConfigUseCaseTests`
  - `SwiftSoupDetailParserTests`
  - `SwiftSoupReaderParserTests`
- Notes:
  - Covers P1-5.1 ListContext attachment and application handoff.
  - Covers P1-5.2 PageRule.sections list parsing and section context attachment.
  - Covers P1-5.3 Detail/Reader context scope narrowing.
  - Covers P1-5.4 TabGroupRule/TabRule expansion into ListTabRule.
  - Xcode reported `BrowseCraftRulesKit @ main (6f54e9b)`.
  - No UI tests were run in this pass.
