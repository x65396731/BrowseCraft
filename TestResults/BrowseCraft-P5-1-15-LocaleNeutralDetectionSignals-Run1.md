# BrowseCraft P5.1.15 Locale-neutral Detection Signals Run 1

- 日期：2026-07-07
- 范围：
  - `BrowseCraftTests/VideoSourceDetectionTests`
  - `BrowseCraftTests/VideoTabDiscoveryTests`

## 命令

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.1.app/Contents/Developer xcodebuild test -workspace /Users/trs/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests -only-testing:BrowseCraftTests/VideoTabDiscoveryTests
```

## 结果

- 状态：通过
- Swift Testing：29 tests / 2 suites / 0 failures
- xcodebuild：`** TEST SUCCEEDED **`
- `.xcresult`：

```text
/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_11-34-42-+0900.xcresult
```

## 覆盖点

- `VideoDetectionLexicon` 作为 detector 内部语义词表集中管理多地区检测 marker，不作为 UI localization layer。
- 日语 playback/list 语义词只辅助结构信号；有 direct media 结构时仍能识别 GenericHTML。
- 只有本地化语义词、没有视频结构时，不产生 supported confidence。
- 西语 account/pay marker 不会在公开内容存在时强制 plugin。
- 本地化 captcha marker 仍进入 plugin boundary，并映射为 `.pluginRequired(.captchaOrAntiBot)`。
- P5.1.14 的 `AddVideoSourceUseCase` 保存、needsReview、unavailable、pluginRequired 分支保持通过。

## 备注

- 本节未新增 Swift 文件，未运行 XcodeGen / pod install。
- P5.1.15a 只新增 Swift 侧 `VideoSourceImportStrings` 入口，用于集中视频导入状态文案；未新增 `Localizable.strings`、string catalog 或多语言 UI 文案。
- Xcode 输出中 XCTest 汇总显示 `Executed 0 tests` 是 Swift Testing 用例的常见显示差异；实际 Swift Testing 汇总为 29 tests 全部通过。
