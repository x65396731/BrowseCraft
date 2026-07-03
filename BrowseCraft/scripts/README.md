# BrowseCraft Scripts

## update-rules-package.sh

Use this script after `BrowseCraftRulesKit` has been committed and pushed to `main`.

中文注释：脚本默认模式会真实刷新 App 侧 RulesKit Swift Package，因此只在确认规则包已 push 后使用。

The script updates the app-side Swift Package pin to the current remote
`BrowseCraftRulesKit` `main` revision, verifies that Xcode resolves the same
revision, then runs `pod install`.

It does not build the app.

```sh
./scripts/update-rules-package.sh
```

Use dry-run/check mode when you only want to confirm script inputs and current
pin state.

中文注释：dry-run/check 只读取远端 main SHA、检查本地 RulesKit HEAD、检查两处 `Package.resolved` 当前 pin，不写文件、不执行 `xcodebuild`、不执行 `pod install`。

```sh
./scripts/update-rules-package.sh --dry-run
./scripts/update-rules-package.sh --check
```
