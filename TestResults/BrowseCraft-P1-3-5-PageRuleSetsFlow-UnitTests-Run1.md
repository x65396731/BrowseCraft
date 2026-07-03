# BrowseCraft P1-3.5 Page RuleSets Flow Unit Tests Run 1

## 测试范围

中文注释：本记录用于保留 P1-3.5 的测试结果，重点确认 V2 `Pages` 与 `RuleSets` 的 list/detail/gallery 主入口可以串成一个最小完整解析流程。

- `BrowseCraftTests/SiteRuleV2CompletenessTests`
- `BrowseCraftTests/SwiftSoupListParserTests`
- `BrowseCraftTests/SwiftSoupDetailParserTests`
- `BrowseCraftTests/SwiftSoupReaderParserTests`

## 执行命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -only-testing:BrowseCraftTests/SwiftSoupListParserTests -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests -only-testing:BrowseCraftTests/SwiftSoupReaderParserTests test
```

## 结果

- 结果：通过
- Swift Testing：19 tests / 4 suites passed
- XCTest 兼容输出：0 tests executed, 0 failures
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_14-53-18-+0900.xcresult`

## 覆盖点

- `RuleSets` 按稳定 id 查找各类规则。
- V2 `PageRule.ruleRefs.list` 驱动列表解析。
- V2 `PageRule.ruleRefs.detail` 驱动详情章节解析。
- V2 `PageRule.ruleRefs.gallery` 驱动阅读页图片解析。
- 同一个 V2 fixture 禁用旧 `list/detail/gallery` 入口后，仍能完成 list -> detail -> reader 最小解析流程。
