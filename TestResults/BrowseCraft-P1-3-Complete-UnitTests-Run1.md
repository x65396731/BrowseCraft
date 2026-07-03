# BrowseCraft P1-3 Complete Unit Tests Run 1

## 测试范围

中文注释：本记录用于保留 P1-3 完整单元测试结果，确认当前 `BrowseCraftTests` 全量用例在 Xcode 26.0.1 下通过。

- `BrowseCraftTests`

## 执行命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild -workspace /Users/trs/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests test
```

## 结果

- 执行时间：2026-07-03 14:55:44 +0900
- 结果：通过
- Swift Package：`BrowseCraftRulesKit @ main (6f54e9b)`
- Swift Testing：31 tests / 9 suites passed
- XCTest 兼容输出：0 tests executed, 0 failures
- xcresult：
  `/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-dddrymidaguvxweqvbjcppofakki/Logs/Test/Test-BrowseCraft-2026.07.03_14-55-30-+0900.xcresult`

## 覆盖点

- V2 `ExtractRule`、字段模型、嵌套规则、请求配置、URL 模板解码。
- `RuleSets` 按稳定 id 查找 list/detail/gallery 等规则。
- V2 `Pages.ruleRefs` 驱动列表、详情、阅读页解析入口。
- `SwiftSoupRuleParser` 的 list -> detail -> reader 最小完整解析流程。
