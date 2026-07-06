# BrowseCraft P5.1.10 VideoSourceDetection Naming + Plugin Run 1

- 日期：2026-07-07
- 范围：`BrowseCraftTests/VideoSourceDetectionTests`
- 命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/VideoSourceDetectionTests
```

## 结果

- 状态：通过
- Swift Testing：9 tests / 1 suite / 0 failures
- xcodebuild：`** TEST SUCCEEDED **`
- `.xcresult`：

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-cmivihkzqbasvdgazoybpgpjhgvv/Logs/Test/Test-BrowseCraft-2026.07.07_08-00-06-+0900.xcresult
```

## 覆盖点

- `VideoAdapter.iframe` 表示内容资料层 iframe/frame 套壳。
- `VideoPlaybackMode.iframe` 表示播放层 iframe/embed/player。
- 普通登录/VIP/会员提示只进入 warnings，不强制 plugin。
- `captcha` / `CryptoJS` / `decrypt` / `encrypted` 等强信号仍进入 plugin。
