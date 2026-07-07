# BrowseCraft P5.1.13 Plugin Boundary Run 1

- 日期：2026-07-07
- 范围：
  - `BrowseCraftTests/VideoSourceDetectionTests`
  - `BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests`

## 命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests
```

## 结果

- 状态：通过
- Swift Testing：26 tests / 2 suites / 0 failures
- xcodebuild：`** TEST SUCCEEDED **`
- `.xcresult`：

```text
/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_10-50-58-+0900.xcresult
```

## 覆盖点

- `VideoSourceImportDecisionResolver` 可把高置信内置视频来源判为 `supported`。
- 中等置信 GenericHTML 来源进入 `needsReview`。
- `no video signals`、低置信度、WebViewRequired、iframe content adapter 未接入都进入 `unavailable`，不作为 plugin fallback。
- 加密播放信号进入 `pluginRequired(.encryptedPlayback)`。
- `.plugin` / `.iframe` unsupported mapper 文案分别指向 Plugin 模块未接入和 iframe content adapter 未接入。

## 备注

- 第一次运行中新增测试样本与 detector 实际评分不匹配，2 个测试断言失败；已修正测试样本和低置信度 synthetic detection 后重跑通过。
- Xcode 输出中 XCTest 汇总显示 `Executed 0 tests` 是 Swift Testing 用例的常见显示差异；实际 Swift Testing 汇总为 26 tests 全部通过。
