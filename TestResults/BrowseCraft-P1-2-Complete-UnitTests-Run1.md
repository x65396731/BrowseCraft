# BrowseCraft P1-2 Complete Unit Tests Run 1

## 测试目的

- 中文注释：本次完整性测试用于确认 P1-2 函数链运行时补齐后，模型解码、列表解析、详情解析、阅读页解析和 URL 模板解析仍保持兼容。
- 中文注释：测试范围限定在 `BrowseCraftTests`，不包含 UI tests。

## 执行命令

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P1-2-Complete-UnitTests-Run1.xcresult \
  test
```

## 结果摘要

- 结果：通过
- Swift Testing：22 tests passed, 0 failures
- Result bundle：`BrowseCraft/TestResults/BrowseCraft-P1-2-Complete-UnitTests-Run1.xcresult`
- RulesKit resolved revision：`6f54e9b`

## 覆盖范围

- ExtractRule 旧格式兼容和 selectorKind/functions 解码。
- ListFields / DetailFields / ChapterRule 字段模型。
- Tag / Comment / Video 语义化嵌套规则。
- RequestConfig 请求优先级和图片请求配置。
- 完整 V2 SiteRule 与 legacy 字段共存解码。
- SwiftSoup list/detail/reader 解析回归。
- P1-2 函数链运行时：
  - 顺序执行
  - fallback
  - replace
  - zlib + Base64 decompressFromBase64
  - selectorKind=current

## 关键日志

```text
✔ Suite ExtractRuleModelTests passed
✔ Suite FieldModelTests passed
✔ Suite NestedRuleModelTests passed
✔ Suite RequestConfigModelTests passed
✔ Suite SiteRuleV2CompletenessTests passed
✔ Suite SwiftSoupDetailParserTests passed
✔ Suite SwiftSoupListParserTests passed
✔ Suite SwiftSoupReaderParserTests passed
✔ Suite URLTemplateModelTests passed
✔ Test run with 22 tests passed
** TEST SUCCEEDED **
```

## 备注

- 中文注释：Xcode 传统 XCTest 汇总中出现 `Executed 0 tests`，是 Swift Testing 用例的显示差异；实际 Swift Testing 汇总显示 22 个测试全部通过。
- 中文注释：本次未执行 UI tests，未执行自动 commit/push/pod install。
