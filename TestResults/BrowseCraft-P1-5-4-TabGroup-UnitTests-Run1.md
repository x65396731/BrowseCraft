# BrowseCraft P1-5.4 TabGroup Unit Tests Run 1

- 中文注释：本次测试用于验证 P1-5.4 的 V2 TabGroupRule/TabRule 能展开为 App 现有 ListTabRule，并保持列表上下文传递。
- Date: 2026-07-03
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -only-testing:BrowseCraftTests/SwiftSoupListParserTests -only-testing:BrowseCraftTests/RequestConfigUseCaseTests test
```

## Result

- Status: Passed
- Executed: 15 tests / 3 suites
- Coverage:
  - `SiteRuleV2CompletenessTests`
  - `SwiftSoupListParserTests`
  - `RequestConfigUseCaseTests`
- Notes:
  - First run failed at compile time because Swift inferred the `pages.flatMap` closure as returning `ListTabRule`; the implementation was changed to explicit array aggregation.
  - `v2ListPagesBecomeAvailableListTabs` asserts TabGroup tabs expand into `discover` and `latest`.
  - `v2TabGroupSelectedTabBecomesDefaultListTab` asserts `selectedTabId` can move the default tab.
  - `refreshSourcePassesListRequestToHTTPClient` asserts the default tab context is now `discover`.
  - Xcode reported `BrowseCraftRulesKit @ main (6f54e9b)`.
  - No UI tests were run in this targeted pass.
