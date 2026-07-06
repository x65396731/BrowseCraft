# BrowseCraft P5.1.11 IframePlayback Run 1

- 日期：2026-07-07
- 范围：
  - `BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests`
  - `BrowseCraftTests/VideoRuntimeMacCMSMappingTests`

## 预处理

本阶段新增了 `BrowseCraft/Application/Runtime/Video/Playback/` 源码文件，因此测试前执行：

```sh
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
```

## 命令

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoRuntimeGenericHTMLMappingTests -only-testing:BrowseCraftTests/VideoRuntimeMacCMSMappingTests
```

## 结果

- 状态：通过
- Swift Testing：14 tests / 2 suites / 0 failures
- xcodebuild：`** TEST SUCCEEDED **`
- `.xcresult`：

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-cmivihkzqbasvdgazoybpgpjhgvv/Logs/Test/Test-BrowseCraft-2026.07.07_08-30-09-+0900.xcresult
```

## 覆盖点

- `GenericHTMLVideoHTMLMapper` 抽到 `iframe[src]` / `embed[src]` 时输出：
  - `candidateMediaKind = .iframe`
  - `status = .pageOnly`
- GenericHTML iframe 相对 URL 可补全为绝对 URL。
- `MacCMSVideoHTMLMapper` 的 `player_aaaa.url` 指向 embed/player 时输出 iframe pageOnly。
- `player_aaaa` 作为 MacCMS player payload 强信号，仍能让 detector 识别为 `macCMS`。

## 中间修复

第一次定向测试中，`videoAdapterDetectorIdentifiesMacCMSFromRouteAndHTMLSignals` 失败：

```text
HTML 中包含 player_aaaa + mac_history + vod_name，但 detector 返回 genericHTML。
```

原因是 `player_aaaa` 虽属于强 MacCMS payload 信号，但原评分只增加 `0.18`，达不到 `macCMS` 阈值。

已修复为：

```text
player_aaaa / mac_url / mac_player / macplayer 命中时作为 MacCMS player payload 强信号，增加 0.72。
/vodtype/ / /vodshow/ / /voddetail/ / /vodplay/ 保持为 route marker 组合信号。
```
