# BrowseCraft Scripts

## regenerate-project.sh

Regenerate the Xcode project after adding, moving or removing source files.

```sh
./scripts/regenerate-project.sh
```

中文注释：依赖全部由 Swift Package Manager 管理，工程只需要 `xcodegen generate`，没有 CocoaPods 步骤。如果 Xcode 正开着工程并提示"文件已被修改"，选"使用磁盘版本"。

It does not build the app.

## update-rules-package.sh

Use this script after `BrowseCraftRulesKit` has been committed and pushed to `main`.

中文注释：脚本默认模式会真实刷新 App 侧 RulesKit Swift Package，因此只在确认规则包已 push 后使用。

The script updates the app-side Swift Package pin to the current remote
`BrowseCraftRulesKit` `main` revision, verifies that Xcode resolves the same
revision. Dependencies are all Swift packages, so there is no `pod install` step.

It does not build the app.

```sh
./scripts/update-rules-package.sh
```

Use dry-run/check mode when you only want to confirm script inputs and current
pin state.

中文注释：dry-run/check 只读取远端 main SHA、检查本地 RulesKit HEAD、检查 `Package.resolved` 当前 pin，不写文件、不执行 `xcodebuild`。

```sh
./scripts/update-rules-package.sh --dry-run
./scripts/update-rules-package.sh --check
```

## check-architecture-boundaries.sh

Runs as a pre-build phase of the `BrowseCraft` target. It rejects forbidden
framework imports in `Domain` and `Application`, APIKit imports outside
`Infrastructure`/`AppContainer`, raw `print` logging, SwiftSoup outside its named
Core adapters, and top-level type references that point against the layer
direction (for example a `Features` type used from `Application`, or an `App`
type used from `Features`).

中文注释：同一模块内 import 检查看不见跨层类型引用，所以脚本会把每层顶层声明的类型名拿去别的层搜索；注释和字符串字面量会先被剥掉。

```sh
./scripts/check-architecture-boundaries.sh
```

## check-ad-configuration.sh

Runs as a pre-build phase of the `BrowseCraft` target. A PROD archive
(`ACTION=install`) that still uses Google's sample rewarded ad unit fails; every
other build only prints a warning.

```sh
BROWSECRAFT_ENVIRONMENT_NAME=PROD ACTION=install ./scripts/check-ad-configuration.sh
```
