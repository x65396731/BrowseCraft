# BrowseCraft P5.1.15 Locale-neutral Detection Signals Run 2

- 日期：2026-07-07
- 范围：
  - `BrowseCraftTests/VideoSourceDetectionTests`
  - `BrowseCraftTests/VideoTabDiscoveryTests`
  - `BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests`

## 命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests
```

## 结果

- 状态：通过
- Swift Testing：38 tests / 3 suites / 0 failures
- xcodebuild：`** TEST SUCCEEDED **`
- `.xcresult`：

```text
/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_11-45-23-+0900.xcresult
```

## 覆盖点

- P5.1.15 locale-neutral detection signals 回归。
- P5.1.14 `AddVideoSourceUseCase` saved / needsReview / unavailable / pluginRequired 分支回归。
- GenericHTML list/detail/playback mapping、WebViewRequired guard、unsupported adapter product-branch messages 回归。

## 备注

- 本轮在 Run 1 基础上追加 `VideoRuntimeGenericHTMLMappingTests`，扩大到 3 个 suite。
- Xcode 输出中 XCTest 汇总显示 `Executed 0 tests` 是 Swift Testing 用例的常见显示差异；实际 Swift Testing 汇总为 38 tests 全部通过。
