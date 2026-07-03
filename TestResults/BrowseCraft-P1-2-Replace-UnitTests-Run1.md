# BrowseCraft P1-2.3 Replace Unit Tests Run 1

## 测试目的

- 中文注释：本次测试用于验证 Rule V2 `ExtractFunction.replace` 在函数链中的运行时行为。
- 中文注释：重点确认 `param` 作为被替换文本、`replacement` 作为替换文本时，章节标题能通过公开解析路径完成清洗。

## 执行命令

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P1-2-Replace-UnitTests-Run1.xcresult \
  test
```

## 结果摘要

- 结果：通过
- Swift Testing：5 tests passed, 0 failures
- Result bundle：`BrowseCraft/TestResults/BrowseCraft-P1-2-Replace-UnitTests-Run1.xcresult`
- RulesKit resolved revision：`6f54e9b`

## 通过用例

- `builtInDetailRuleParsesOnlyScopedChapters()`
- `builtInDetailRuleDoesNotFallbackToGlobalChapterLinks()`
- `v2ChapterRulesApplyFunctionChains()`
- `v2ChapterRulesUseFallbackWhenPrimaryResultIsBlankOrMissing()`
- `v2ChapterRulesApplyReplaceFunctionInChain()`

## 关键日志

```text
✔ Test v2ChapterRulesApplyReplaceFunctionInChain() passed
✔ Suite SwiftSoupDetailParserTests passed
✔ Test run with 5 tests passed
** TEST SUCCEEDED **
```

## 备注

- 中文注释：Xcode 传统 XCTest 汇总中出现 `Executed 0 tests`，是 Swift Testing 用例的显示差异；实际 Swift Testing 汇总显示 5 个测试全部通过。
- 中文注释：`decompressFromBase64` 尚未实现，因为当前规则模型没有声明压缩算法，避免在执行器里加入隐式假设。
