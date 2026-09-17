# BrowseCraft Scripts

## regenerate-project.sh

Regenerate the Xcode project after adding, moving or removing source files.

```sh
./scripts/regenerate-project.sh
```

中文注释：依赖全部由 Swift Package Manager 管理，工程只需要 `xcodegen generate`，没有 CocoaPods 步骤。如果 Xcode 正开着工程并提示"文件已被修改"，选"使用磁盘版本"。

中文注释：工程文件是生成物且不入库，因此签名团队等设置必须写在 `project.yml`（`settings.base.DEVELOPMENT_TEAM`）。在 Xcode 的 Signing & Capabilities 里改只在下次重新生成前有效。

It does not build the app.

## check-architecture-boundaries.sh

Pre-build gate for layer boundaries. It runs on every build and never modifies anything.

```sh
./scripts/check-architecture-boundaries.sh
```

中文注释：2026-09-18 起闸门覆盖以下内容，以「今天的取值」为基线，阻止继续漂移：

- import 检查匹配所有写法：`import X`、`@preconcurrency import X`、`@_exported import X`、`import struct X.Y`、`import X.Sub`。
- 类型引用方向新增 Features→Infrastructure、Shared→Application、Shared→Infrastructure；`declared_types` 识别 `@Observable`、`nonisolated`、`package`、`open` 等修饰。
- `print(` 与 `try!` 禁用扩展到 App 与四个包（Core / Domain / Runtime / APIKit）的 Sources。

已存在的命中登记在 `scripts/architecture-boundary-exemptions.txt`，每行「路径 标识」（路径相对仓库根，包用 `../BrowseCraftXxx/...`）。
豁免只允许收敛、不允许新增未经审阅的条目；删掉一行即恢复对该处的检查。

## check-swiftsoup-override.sh

Verify that the local SwiftSoup override package (`../SwiftSoup`) sits at the exact commit
`BrowseCraftCore/Package.swift` pins, with a clean working tree. It runs as a pre-build phase
and only checks; it never modifies anything.

```sh
./scripts/check-swiftsoup-override.sh
```

中文注释：SwiftSoup 走两条路——Core 按 commit 锁定自家 fork（`swift test` 用这条），工程用 `../SwiftSoup`
本地包覆盖整张依赖图（Xcode 构建用这条，Readium 也被指到 fork）。两条路必须是同一个 commit，否则
`swift test` 和 Xcode 看到的解析器不是同一份。首次拉取本地覆盖包：

```sh
git clone --branch browsecraft/text-whitespace-fix git@github.com:x65396731/SwiftSoup.git ../SwiftSoup
```

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
