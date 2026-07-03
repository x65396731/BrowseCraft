# BrowseCraft P1-2.4 Decompress Unit Tests Run 1

## 测试目的

- 中文注释：本次测试用于验证 Rule V2 `ExtractFunction.decompressFromBase64` 在函数链中的运行时行为。
- 中文注释：当前实现明确限定为 Base64 包裹的 zlib 数据，本测试用固定 fixture 防止算法边界漂移。

## 执行命令

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests/SwiftSoupDetailParserTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P1-2-Decompress-UnitTests-Run1.xcresult \
  test
```

## 结果摘要

- 结果：通过
- Swift Testing：6 tests passed, 0 failures
- Result bundle：`BrowseCraft/TestResults/BrowseCraft-P1-2-Decompress-UnitTests-Run1.xcresult`
- RulesKit resolved revision：`6f54e9b`

## 通过用例

- `builtInDetailRuleParsesOnlyScopedChapters()`
- `builtInDetailRuleDoesNotFallbackToGlobalChapterLinks()`
- `v2ChapterRulesApplyFunctionChains()`
- `v2ChapterRulesUseFallbackWhenPrimaryResultIsBlankOrMissing()`
- `v2ChapterRulesApplyReplaceFunctionInChain()`
- `v2ChapterRulesApplyDecompressFromBase64FunctionInChain()`

## 关键日志

```text
✔ Test v2ChapterRulesApplyDecompressFromBase64FunctionInChain() passed
✔ Suite SwiftSoupDetailParserTests passed
✔ Test run with 6 tests passed
** TEST SUCCEEDED **
```

## 备注

- 中文注释：fixture `e75mjYEJAA==` 是字符串“第04”的 zlib 压缩结果再 Base64 编码。
- 中文注释：Xcode 传统 XCTest 汇总中出现 `Executed 0 tests`，是 Swift Testing 用例的显示差异；实际 Swift Testing 汇总显示 6 个测试全部通过。
