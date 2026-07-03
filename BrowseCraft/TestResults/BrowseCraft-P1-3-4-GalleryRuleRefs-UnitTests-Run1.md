# BrowseCraft P1-3.4 Gallery RuleRefs Unit Tests Run 1

## 测试范围

中文注释：本记录用于保留 P1-3.4 的测试结果，重点确认阅读页图片入口能从 `PageRule.ruleRefs.gallery` 接到 `RuleSets.galleryRules[id]`，且旧阅读页解析仍可回归。

- `BrowseCraftTests/SiteRuleV2CompletenessTests`
- `BrowseCraftTests/SwiftSoupReaderParserTests`

## 执行命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -only-testing:BrowseCraftTests/SwiftSoupReaderParserTests test
```

## 结果

- 结果：通过
- Swift Testing：8 tests / 2 suites passed
- XCTest 兼容输出：0 tests executed, 0 failures
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_14-50-30-+0900.xcresult`

## 覆盖点

- `primaryGalleryRule` 优先使用 V2 `PageRule.ruleRefs.gallery -> RuleSets.galleryRules`。
- `SwiftSoupRuleParser.parseReader` 默认入口可解析 V2 gallery rule。
- 旧版阅读页元数据和图片解析回归仍通过。
