# BrowseCraft P1-2.2 Fallback Unit Tests Run 1

## 测试目的

- 中文注释：本次测试用于验证 Rule V2 `ExtractRule.fallback` 在章节解析中的运行时行为。
- 中文注释：重点覆盖主规则结果为空白字符串、主规则 selector 缺失时，解析器是否继续尝试备用规则。

## 执行命令

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P1-2-Fallback-UnitTests-Run1.xcresult \
  test
```

## 结果摘要

- 结果：通过
- Swift Testing：4 tests passed, 0 failures
- Result bundle：`BrowseCraft/TestResults/BrowseCraft-P1-2-Fallback-UnitTests-Run1.xcresult`
- RulesKit resolved revision：`6f54e9b`

## 通过用例

- `builtInDetailRuleParsesOnlyScopedChapters()`
- `builtInDetailRuleDoesNotFallbackToGlobalChapterLinks()`
- `v2ChapterRulesApplyFunctionChains()`
- `v2ChapterRulesUseFallbackWhenPrimaryResultIsBlankOrMissing()`

## 关键日志

```text
✔ Test v2ChapterRulesUseFallbackWhenPrimaryResultIsBlankOrMissing() passed
✔ Suite SwiftSoupDetailParserTests passed
✔ Test run with 4 tests passed
** TEST SUCCEEDED **
```

## 备注

- 中文注释：Xcode 传统 XCTest 汇总中出现 `Executed 0 tests`，是 Swift Testing 用例的显示差异；实际 Swift Testing 汇总显示 4 个测试全部通过。
