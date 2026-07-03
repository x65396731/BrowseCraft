# BrowseCraft P2-3.2 List Debug UseCase Unit Tests Run 1

中文注释：本记录用于保留 P2-3.2 RuleDebugger 列表调试应用层测试结果；`.xcresult` 仅作为本机临时结果包，不作为长期提交物。

## Preparation

```sh
xcodegen generate
env -u GEM_HOME -u GEM_PATH -u RUBYLIB -u RUBYOPT pod install
```

中文注释：P2-3.1/P2-3.2 新增 Swift 文件，测试前按 XcodeGen 规则重新生成工程，并重新接入 CocoaPods。生成的 `pbxproj` 仍不作为提交物。

## Command

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/RuleDebugUseCaseTests -resultBundlePath /private/tmp/BrowseCraft-P2-3-2-ListDebugUseCase-UnitTests.xcresult
```

## Result

- Status: Passed
- Test suites: 1
- Tests: 3 passed
- Failures: 0
- Xcode: `/Applications/Xcode.app/Contents/Developer`
- Swift Package resolved: `BrowseCraftRulesKit @ main (cfcbd75)`

## Result Bundle

```text
/private/tmp/BrowseCraft-P2-3-2-ListDebugUseCase-UnitTests.xcresult
```

中文注释：该 `.xcresult` 位于临时目录，可用于本机短期复查日志；长期记录以本 Markdown 为准。

## Covered Scope

- P2-3.2: List debug use case returns a successful `RuleDebugSession`.
- P2-3.2: Request log records URL, request summary, and response content length.
- P2-3.2: Preview items are returned without writing cache.
- P2-3.2: Empty list result returns a selectorEmpty warning session.
- P2-3.2: Request failure returns a failed session with classified request issue.

## Notes

- 中文注释：测试期间出现 iOS Simulator WebCore/WebKit accessibility duplicate class warning；测试未失败，当前判断为模拟器运行时噪声。

## Not Run

- 中文注释：本次未执行全量 `BrowseCraftTests`。
- 中文注释：本次未执行 UI 自动化测试。
- 中文注释：本次未执行单独的 build 命令。
