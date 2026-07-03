# BrowseCraft P1-5.3 Context Scope Unit Tests Run 1

- 中文注释：本次测试用于验证 P1-5.3 的列表来源上下文会传入 Detail/Reader 解析，并按来源 section 缩小解析范围。
- Date: 2026-07-03
- Xcode: `/Applications/Xcode-26.0.1.app/Contents/Developer`
- Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RequestConfigUseCaseTests -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests -only-testing:BrowseCraftTests/SwiftSoupReaderParserTests test
```

## Result

- Status: Passed
- Executed: 16 tests / 3 suites
- Coverage:
  - `RequestConfigUseCaseTests`
  - `SwiftSoupDetailParserTests`
  - `SwiftSoupReaderParserTests`
- Notes:
  - `loadChaptersPassesDetailRequestToHTTPClient` asserts Detail parsing receives `ContentItem.listContext`.
  - `loadReaderPassesGalleryRequestToHTTPClient` asserts Reader parsing receives `ContentItem.listContext`.
  - `v2DetailChaptersUseListContextScope` asserts Detail chapters are limited to the context section.
  - `v2ReaderImagesUseListContextScope` asserts Reader images are limited to the context section.
  - Xcode reported `BrowseCraftRulesKit @ main (6f54e9b)`.
  - No UI tests were run in this targeted pass.
