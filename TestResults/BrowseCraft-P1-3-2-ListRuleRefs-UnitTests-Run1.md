# BrowseCraft P1-3.2 List RuleRefs Unit Tests Run 1

## 测试范围

中文注释：本记录用于保留 P1-3.2 的测试结果，重点确认列表入口能从 `PageRule.ruleRefs.list` 接到 `RuleSets.listRules[id]`，且旧列表规则仍可回归。

- `BrowseCraftTests/SiteRuleV2CompletenessTests`
- `BrowseCraftTests/SwiftSoupListParserTests`

## 执行命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -only-testing:BrowseCraftTests/SwiftSoupListParserTests test
```

## 结果

- 结果：通过
- Swift Testing：6 tests / 2 suites passed
- XCTest 兼容输出：0 tests executed, 0 failures
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_14-43-21-+0900.xcresult`

## 覆盖点

- `RuleSets` 按稳定 id 查找 list/detail/gallery/search 规则。
- V2 list page 可生成 `availableListTabs`。
- `primaryListRule` 优先使用 V2 `PageRule.ruleRefs.list -> RuleSets.listRules`。
- `SwiftSoupRuleParser.parseList(html:source:)` 默认入口可解析 V2 list rule。
- 旧版内置列表解析回归仍通过。
