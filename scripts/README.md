# BrowseCraft Scripts

## regenerate-project.sh

Regenerate the Xcode project and restore CocoaPods integration in one command.

中文注释：不要手动拆开执行 `xcodegen generate` 和裸 `pod install`。本项目里 `pod install` 必须清掉 RVM 注入的 `GEM_HOME/GEM_PATH`，否则 Homebrew CocoaPods 可能混用 Ruby/Gem 环境并报 `rexml` 缺失。

```sh
./scripts/regenerate-project.sh
```

The script runs:

```sh
xcodegen generate
env -u GEM_HOME -u GEM_PATH pod install
```

It does not build the app.

中文注释：如果 Xcode 正开着工作区，重生成后 Xcode 可能提示"文件已被修改"——务必选"使用磁盘版本"（或先关掉工作区再跑脚本）。保留 Xcode 内存里的旧版本会丢掉 CocoaPods 集成，打出的包不内嵌 Alamofire/GRDB/Nuke 等框架。

## check-pods-integration.sh

Runs first among the `BrowseCraft` pre-build phases. It fails the build when the
project file has no `[CP] Embed Pods Frameworks` phase or `Pods/Manifest.lock`
is missing, i.e. when XcodeGen regenerated the project but `pod install` did
not finish.

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
