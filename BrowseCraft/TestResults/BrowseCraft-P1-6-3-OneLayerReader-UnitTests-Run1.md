# BrowseCraft P1-6.3 One-layer Reader Unit Tests Run 1

中文注释：本记录用于保留 P1-6.3 的目标测试结果，重点确认 Pepper&Carrot 这类一层列表直达阅读源不会退回二层详情页章节解析。

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RequestConfigUseCaseTests test
```

## Result

- Status: Passed
- Test suite: `RequestConfigUseCaseTests`
- Tests: 5 passed
- Failures: 0
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Swift Package resolved: `BrowseCraftRulesKit @ main (6f54e9b)`

## Covered Tests

- `refreshSourcePassesListRequestToHTTPClient`
- `loadChaptersPassesDetailRequestToHTTPClient`
- `loadReaderPassesGalleryRequestToHTTPClient`
- `loadChaptersTreatsDetailURLAsSingleChapterWhenRuleRequestsIt`
- `loadReaderTreatsDetailURLAsChapterAndSkipsDetailParsingWhenRuleRequestsIt`

## Notes

- 中文注释：本次是目标单元测试，不包含 UI 测试。
- 中文注释：本次没有执行 `pod install`，没有刷新 Swift Package，未改动 `Package.resolved`。
