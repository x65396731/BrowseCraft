# BrowseCraft P1-5.1 ListContext Unit Tests Run 1

- 中文注释：本次测试用于验证 P1-5.1 的列表来源上下文会从刷新用例附加到保存的 ContentItem。
- Date: 2026-07-03
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RequestConfigUseCaseTests test
```

## Result

- Status: Passed
- Executed: 3 tests / 1 suite
- Coverage:
  - `refreshSourcePassesListRequestToHTTPClient`
  - `loadChaptersPassesDetailRequestToHTTPClient`
  - `loadReaderPassesGalleryRequestToHTTPClient`
- Notes:
  - `refreshSourcePassesListRequestToHTTPClient` now also asserts `pageId`, `tabId`, `listRuleId`, and `sectionRole`.
  - Xcode reported `BrowseCraftRulesKit @ main (6f54e9b)`.
  - No UI tests were run in this targeted pass.
