# BrowseCraft P1-2.5 Current Selector Unit Tests Run 1

## 测试目的

- 中文注释：本次测试用于验证 Rule V2 `selectorKind=current` 的运行时行为。
- 中文注释：重点确认章节 item 自身可以作为 title/url 的抽取对象，不再依赖 legacy `selector="this"` 字符串。

## 执行命令

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P1-2-CurrentSelector-UnitTests-Run1.xcresult \
  test
```

## 结果摘要

- 结果：通过
- Swift Testing：7 tests passed, 0 failures
- Result bundle：`BrowseCraft/TestResults/BrowseCraft-P1-2-CurrentSelector-UnitTests-Run1.xcresult`
- RulesKit resolved revision：`6f54e9b`

## 通过用例

- `builtInDetailRuleParsesOnlyScopedChapters()`
- `builtInDetailRuleDoesNotFallbackToGlobalChapterLinks()`
- `v2ChapterRulesApplyFunctionChains()`
- `v2ChapterRulesUseFallbackWhenPrimaryResultIsBlankOrMissing()`
- `v2ChapterRulesApplyReplaceFunctionInChain()`
- `v2ChapterRulesApplyDecompressFromBase64FunctionInChain()`
- `v2ChapterRulesUseCurrentSelectorKindForItemText()`

## 关键日志

```text
✔ Test v2ChapterRulesUseCurrentSelectorKindForItemText() passed
✔ Suite SwiftSoupDetailParserTests passed
✔ Test run with 7 tests passed
** TEST SUCCEEDED **
```

## 备注

- 中文注释：`selectorKind=current` 当前明确返回当前元素；`jsonPath/xpath` 在 parser 中会报 unsupported，避免误走 CSS selector。
- 中文注释：Xcode 传统 XCTest 汇总中出现 `Executed 0 tests`，是 Swift Testing 用例的显示差异；实际 Swift Testing 汇总显示 7 个测试全部通过。
