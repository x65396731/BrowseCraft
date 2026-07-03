# BrowseCraft P2-2.1 Rule Package Codec Unit Tests Run 1

中文注释：本记录用于保留 P2-2.1 BrowseCraft 自有规则包格式与编解码测试结果；`.xcresult` 仅作为本机临时结果包，不作为长期提交物。

## Preparation

```sh
xcodegen generate
env -u GEM_HOME -u GEM_PATH -u RUBYLIB -u RUBYOPT pod install
```

中文注释：P2-2.1 新增 Swift 文件，测试前按 XcodeGen 规则重新生成工程，并重新接入 CocoaPods。

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RulePackageUseCaseTests
```

## Result

- Status: Passed
- Test suites: 1
- Tests: 4 passed
- Failures: 0
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Swift Package resolved: `BrowseCraftRulesKit @ main (cfcbd75)`

## Result Bundle

```text
/Users/xiefei/Library/Developer/Xcode/DerivedData/BrowseCraft-dsebykgpjnzswqalzshucwnskjrv/Logs/Test/Test-BrowseCraft-2026.07.03_22-20-29-+0900.xcresult
```

中文注释：该 `.xcresult` 位于 DerivedData，可用于本机复查日志；长期记录以本 Markdown 为准。

## Covered Scope

- P2-2.1: Encode BrowseCraft rule package JSON envelope.
- P2-2.1: Decode package and verify `formatVersion` / `kind`.
- P2-2.1: Preserve metadata and embedded `SiteRule`.
- P2-2.1: Reject checksum mismatch.
- P2-2.1: Reject unsupported package kind.
- P2-2.1: Reject unsupported format version.

## Notes

- 中文注释：测试期间出现 iOS Simulator WebCore/WebKit accessibility duplicate class warning；测试未失败，当前判断为模拟器运行时噪声。

## Not Run

- 中文注释：本次未执行全量 `BrowseCraftTests`。
- 中文注释：本次未执行 UI 自动化测试。
- 中文注释：本次未执行单独的 build 命令。
