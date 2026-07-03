# BrowseCraft P1-3.3 Detail RuleRefs Unit Tests Run 1

## 测试范围

中文注释：本记录用于保留 P1-3.3 的测试结果，重点确认详情入口能从 `PageRule.ruleRefs.detail` 接到 `RuleSets.detailRules[id]`，且旧详情章节解析仍可回归。

- `BrowseCraftTests/SiteRuleV2CompletenessTests`
- `BrowseCraftTests/SwiftSoupDetailParserTests`

## 执行命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests test
```

## 结果

- 结果：通过
- Swift Testing：13 tests / 2 suites passed
- XCTest 兼容输出：0 tests executed, 0 failures
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_14-47-43-+0900.xcresult`

## 覆盖点

- `primaryDetailRule` 优先使用 V2 `PageRule.ruleRefs.detail -> RuleSets.detailRules`。
- `SwiftSoupRuleParser.parseDetailChapters` 默认入口可解析 V2 detail rule。
- `treatDetailURLAsChapter` 判断对齐 `primaryDetailRule`。
- 旧版详情章节作用域和 V2 函数链解析回归仍通过。
