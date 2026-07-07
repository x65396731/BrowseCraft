# BrowseCraft P5.1.15 Locale-neutral Detection Signals Run 3

- 日期：2026-07-07
- 范围：
  - `BrowseCraftTests/VideoSourceDetectionTests`
  - `BrowseCraftTests/VideoTabDiscoveryTests`
  - `BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests`

## 事前检查

```sh
plutil -lint BrowseCraft/en.lproj/Localizable.strings BrowseCraft/zh-Hans.lproj/Localizable.strings
```

- `BrowseCraft/en.lproj/Localizable.strings`: OK
- `BrowseCraft/zh-Hans.lproj/Localizable.strings`: OK

新增本地化资源后已执行：

```sh
./scripts/regenerate-project.sh
```

该脚本完成 `xcodegen generate` 并恢复 CocoaPods integration。

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
/Users/trs/Library/Developer/Xcode/DerivedData/BrowseCraft-ekyodtkldclxfmcsueisismacgpi/Logs/Test/Test-BrowseCraft-2026.07.07_11-50-21-+0900.xcresult
```

## 覆盖点

- `VideoSourceImportStrings` 已从 `Localizable.strings` key 读取视频导入文案。
- 新增 `en.lproj` / `zh-Hans.lproj` 最小本地化资源后，工程生成、Pods 集成和定向测试均通过。
- P5.1.15 detection lexicon、P5.1.14 source import 分支、GenericHTML runtime mapping 继续通过。

## 备注

- 本节只新增视频导入相关本地化 key，不迁移全项目文案。
- Xcode 输出中 XCTest 汇总显示 `Executed 0 tests` 是 Swift Testing 用例的常见显示差异；实际 Swift Testing 汇总为 38 tests 全部通过。
