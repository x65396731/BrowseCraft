# BrowseCraft P1-6.4 Package Refresh Script Audit

中文注释：本记录用于保留 P1-6.4 对 RulesKit package 刷新脚本的检查结果，目标是确认脚本可以先 dry-run 检查，再由用户明确触发真实刷新。

## Scope

- Script: `BrowseCraft/scripts/update-rules-package.sh`
- Documentation: `BrowseCraft/scripts/README.md`
- Target package: `git@github.com:x65396731/BrowseCraftRulesKit.git`
- Target branch: `main`

## Implemented

- 中文注释：新增 `--dry-run` / `--check` 模式，用于检查脚本输入和当前 pin，不写文件。
- 中文注释：dry-run/check 模式仍检查：
  - `BrowseCraft.xcworkspace` 路径存在。
  - project 与 workspace 两处 `Package.resolved` 文件存在。
  - 远端 `BrowseCraftRulesKit` `main` 可以解析到 40 位 SHA。
  - 本地 `BrowseCraftRulesKit` 若存在，必须干净，且 HEAD 与远端 main SHA 一致。
  - 两处 `Package.resolved` 都包含 `browsecraftruleskit` pin，并打印 current / target revision。
- 中文注释：dry-run/check 模式不会执行：
  - `Package.resolved` 写入。
  - `xcodebuild -resolvePackageDependencies`。
  - `pod install`。
  - App build。
- 中文注释：默认模式保持原行为：更新两处 `Package.resolved`，执行 package resolve 验证，再执行 `pod install`，不 build。

## Static Check

```sh
sh -n BrowseCraft/scripts/update-rules-package.sh
```

Result: Passed

## Dry-run Guard Test

```sh
./scripts/update-rules-package.sh --help
```

Result: Passed

```sh
./scripts/update-rules-package.sh --dry-run
```

Result: Expected failure

```text
[update-rules-package] ERROR: BrowseCraftRulesKit has uncommitted changes. Commit/push or stash them before updating the app package.
```

中文注释：当前 `BrowseCraftRulesKit` 仍有 P1-6.2 的未提交测试改动，dry-run 在读取远端和写入 `Package.resolved` 前提前停止，说明规则包 dirty guard 生效。

## Not Run In This Step

- 中文注释：本轮没有执行成功路径的远端 SHA 检查，因为当前 RulesKit dirty guard 会先拦截。
- 中文注释：本轮没有执行默认刷新模式，因此没有改动 `Package.resolved`，没有执行 `xcodebuild`，没有执行 `pod install`。
