# BrowseCraft Scripts

## regenerate-project.sh

Regenerate the Xcode project after adding, moving or removing source files.

```sh
./scripts/regenerate-project.sh
```

中文注释：依赖全部由 Swift Package Manager 管理，工程只需要 `xcodegen generate`，没有 CocoaPods 步骤。如果 Xcode 正开着工程并提示"文件已被修改"，选"使用磁盘版本"。

中文注释：工程设置写在 `project.yml`（`settings.base.DEVELOPMENT_TEAM`），条款见 `BCA-BUILD-004`。在 Xcode 的 Signing & Capabilities 里改只在下次重新生成前有效。

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
- `BCA-BUILD-005` `scripts/architecture-boundary-exemptions.txt` 的豁免只允许收敛、不允许新增未经审阅的条目；
  删掉一行即恢复对该处的检查。

## check-localization.py

Post-compile gate for localization. It runs after the `BrowseCraft` target compiles its sources and never modifies anything.

```sh
./scripts/check-localization.py <Objects-normal 目录>
```

中文注释：不变量是「编译器认定要本地化的每一个键，en / zh-Hans / zh-Hant 三份 `Localizable.strings` 里都必须有」，
另外三份文件的键集合必须完全一致。键从两处取：SwiftUI 的 `Text` / `Label` / `Section` / `String(localized:)`
读 swiftc 在 `SWIFT_EMIT_LOC_STRINGS: YES` 下写出的 `.stringsdata`；`NSLocalizedString` swiftc 不提取，
从源码取第一个字面量参数。

- 闸门看不到的一类：字面量先放进 `String`，再交给 `Text(someString)`、`.accessibilityValue(someString)`——
  SwiftUI 逐字显示、不查表。这类要在源头写成 `NSLocalizedString(...)`，写对了就自动进入闸门视野。
- 上线当天已缺翻译的键登记在 `scripts/localization-missing-baseline.txt`，只许收敛：补上翻译后删掉那一行，
  新写的文案直接三语补齐，不登记。

## check-swiftsoup-override.sh

Verify that the local SwiftSoup override package (`../SwiftSoup`) sits at the exact commit
`BrowseCraftCore/Package.swift` pins, with a clean working tree. It runs as a pre-build phase
and only checks; it never modifies anything.

```sh
./scripts/check-swiftsoup-override.sh
```

中文注释：SwiftSoup 走两条路——Core 按 commit 锁定自家 fork（`swift test` 用这条），工程用 `../SwiftSoup`
本地包覆盖整张依赖图（Xcode 构建用这条，Readium 也被指到 fork）。两条路必须是同一个 commit（`BCA-BUILD-002`），否则
`swift test` 和 Xcode 看到的解析器不是同一份。首次拉取本地覆盖包：

```sh
git clone --branch browsecraft/text-whitespace-fix git@github.com:x65396731/SwiftSoup.git ../SwiftSoup
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

## check-bundled-image-assets.sh

Pre-build gate for bundled bitmap assets. It runs on every build and never modifies anything.

```sh
./scripts/check-bundled-image-assets.sh
```

中文注释：资产目录里的位图不被任何既有用例覆盖——改错格式的表现是界面空白而不是报错，多带几档冗余
scale 槽位的表现是包体悄悄变大而没人发现。闸门按 `scripts/bundled-image-asset-budgets.txt` 的显式声明检查：

- `BCA-BUILD-006` 资产目录里的每个 `imageset` / `appiconset` 都必须在声明文件里登记，新增资产会因为没登记
  而失败；声明里的每个条目都必须真的存在，源字节不超上限，像素尺寸符合声明；
- `BCA-BUILD-007` 单档形态还要求恰好一张 `.png`、`Contents.json` 不带 scale 槽位，并且
  `compression-type: lossy` 标记与声明的形态双向一致——声明为 lossy 的必须标，声明为无损的不许标。

形态怎么选有实测依据，逐项数据在审计报告 5.4.1：占位图一律被缩放到版面框，多档槽位无收益；
渲染宽度远小于原生分辨率的图标 lossy 后在真实渲染宽度上的 SSIM 仍有 0.990 以上，
而按接近原生分辨率铺满屏幕的图（视频详情占位图）只剩 0.964，因此保持无损。

运行期那一半由 `BrowseCraftTests/Shared/Resources/BundledImageAssetTests.swift` 把关：它读同一份声明，
验证编译进 App 之后每张资产还能解出 `CGImage` 且像素尺寸与声明一致。两处共用一份声明，不会互相漂移。

## check-ad-configuration.sh

Runs as a pre-build phase of the `BrowseCraft` target. A PROD archive
(`ACTION=install`) that still uses Google's sample rewarded ad unit fails; every
other build only prints a warning.

```sh
BROWSECRAFT_ENVIRONMENT_NAME=PROD ACTION=install ./scripts/check-ad-configuration.sh
```

## check-docs.py

文档闸门。执行 [`docs/README.md`](../docs/README.md) 第 3–5 节定义的形态与条款规则；它只执行，不定义。
改动 C 类文档、`docs/STATUS.md` 或 `AGENTS.md` 后，提交前跑一次（`BCA-DOC-010`）。

```sh
python3 scripts/check-docs.py
```

十一项检查：A1 定义点唯一、域在受控词表内、H 类归档不承载定义点；A2 引用到的 ID 都有定义点
（`BCA-*` 查本仓库，`BC-*` 查 fwq 的 C 类）；A3 不为 fwq 已定义的 ID 另写定义点；A4 C 类无状态串头部行；
A5 C 类无 commit 哈希与测试计数；A6 C 类无带日期的章节标题；A7 链接可解析、无绝对主机路径；
A8 `docs/STATUS.md` 每格落枚举或形态；A9 根 `HANDOFF.md` 只承载四样东西（行数与 commit 哈希数是信号，
阈值的唯一声明点在脚本里，文档不复述数值）；A10 文档点名的类型必须在源码里存在（`BCA-DOC-014`）；A11 承载定义点的文档必须被 git 跟踪（`BCA-DOC-015`）——
不被跟踪的文档（如 `.gitignore` 掉的 `AGENTS.md`）只能写引用点，条款正文放进去等于那条合同不在仓库里。

围栏代码块在 A1、A4–A7、A9 与 A10 前一律剥掉——里面的 ID 是语法示例、哈希是命令输出、`[](…)` 不会被渲染成链接。
A2 与 A3 要读 fwq 仓库（缺省 `~/Desktop/fwq`，用 `--fwq` 改），A10 要读四个兄弟包的源码；
**这些仓库不可达时对应检查跳过并如实报告跳过，不静默通过**。

A10 的语料含 App 与四个包的 `Sources/`、`Tests/`、`Package.swift`、`project.yml`，外加仓库树的
目录名与文件名——文档引用 `TestDoubles/`、`UseCases/` 这类路径段是合法的。反引号内以 `*` 开头的
记号按家族通配处理：源码里有任一以它结尾的符号即成立（`*PersistenceCoordinator` 实有 7 个）。
外部符号白名单在 `scripts/docs-external-symbols.txt`。它不接进 pre-build 阶段：文档闸门失败不应阻断代码 build。
