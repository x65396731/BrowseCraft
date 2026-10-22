# BrowseCraft Scripts

## regenerate-project.sh

Regenerate the Xcode project after adding, moving or removing source files.

```sh
./scripts/regenerate-project.sh
```

中文注释：依赖全部由 Swift Package Manager 管理，工程只需要 `xcodegen generate`，没有 CocoaPods 步骤。如果 Xcode 正开着工程并提示"文件已被修改"，选"使用磁盘版本"。

中文注释：工程设置写在 `project.yml`（`settings.base.DEVELOPMENT_TEAM`），条款见 `BCA-BUILD-004`。在 Xcode 的 Signing & Capabilities 里改只在下次重新生成前有效。

It does not build the app.

## ci_scripts/ci_post_clone.sh（Xcode Cloud）

Xcode Cloud 克隆完仓库后自动执行，本机不用跑。它把五个包仓库克隆到上一级目录、从加密环境变量写出
`Config/CatalogEncryption.*.local.xcconfig`、再用锁定版本的 XcodeGen 生成工程。工作流需配置两个 Secret：
`BC_GITHUB_TOKEN`（五个包仓库的只读 fine-grained token）与 `BC_CATALOG_ENCRYPTION_KEYS`（生产目录密钥）。
升级本机 XcodeGen 时同步改脚本里的 `XCODEGEN_VERSION`。
构建号分段：Xcode Cloud 从 1000 起自增，本机上传用 56–999（见 `project.yml` 的 `CURRENT_PROJECT_VERSION` 注释）。

## check-architecture-boundaries.sh

Pre-build gate for layer boundaries. It runs on every build and never modifies anything.

```sh
./scripts/check-architecture-boundaries.sh
```

中文注释：闸门覆盖以下内容，以当前取值为基线，阻止继续漂移：

- import 检查匹配所有写法：`import X`、`@preconcurrency import X`、`@_exported import X`、`import struct X.Y`、`import X.Sub`。
- 类型引用方向包含 Features→Infrastructure、Shared→Application、Shared→Infrastructure；`declared_types` 识别 `@Observable`、`nonisolated`、`package`、`open` 等修饰。
- `print(` 与 `try!` 禁用扩展到 App 与五个包（Core / Domain / Runtime / APIKit / Log）的 Sources。
- 只有一种日志（`BCA-OBS-010`）：`debugPrint(`、`NSLog(`、`os_log(` 与已删除的 AppDebugLog、RuleRuntimeDebugLog 一律禁用，
  `Logger(` 与 `import OSLog` 只许出现在 `BrowseCraft/Shared/Logging/OSLogSink.swift`。
- `.text` 日志字段只许出现在 `AppLog.debug(` 调用里（`BCA-OBS-012`）：按括号配平找出 info 及以上调用里的 `.text(`，命中即失败。
- `try?` 只许收敛（`BCA-OBS-015`）：按文件计数，超过 `scripts/try-optional-baseline.txt` 登记数即失败；同一行带 `// try?: <理由>` 的不计。
- `BrowseCraftRuleModels` 不得依赖 SwiftSoup 与解析目标。
- Swift 6 语言模式：`project.yml` 的 `SWIFT_VERSION` 必须是 `6.0`，五个包的 manifest 必须是 `swift-tools-version: 6.0`
  并显式声明 `.swiftLanguageMode(.v6)`。

它拒绝的内容：`Domain` 与 `Application` 里的禁用框架 import、`Infrastructure/` 与 `App/Composition/` 之外的 APIKit import、
裸 `print`、SwiftSoup 越出 Core 的具名适配器，以及逆着层方向的顶层类型引用（例如 `Application` 用了 `Features` 的类型，
`Features` 用了 `App` 的类型）。同一模块内 import 检查看不见跨层类型引用，所以脚本会把每层顶层声明的类型名拿去别的层搜索；
注释和字符串字面量会先被剥掉。

已存在的命中登记在 `scripts/architecture-boundary-exemptions.txt`，每行「路径 标识」（路径相对仓库根，包用 `../BrowseCraftXxx/...`）。
- `BCA-BUILD-005` `scripts/architecture-boundary-exemptions.txt` 的豁免只允许收敛、不允许新增未经审阅的条目；
  删掉一行即恢复对该处的检查。

## check-localization.py

Post-compile gate for localization. It runs after the `BrowseCraft` target compiles its sources and never modifies anything.

```sh
./scripts/check-localization.py [<Objects-normal 目录>]
```

中文注释：不带参数时读构建阶段提供的 `$OBJECT_FILE_DIR_normal`；两者都没有时报错退出，所以在命令行单独跑要先构建一次，再把目录传进去。

中文注释：不变量是「编译器认定要本地化的每一个键，每种界面语言的 `Localizable.strings` 里都必须有」（`BCA-BUILD-009`），
另外各份文件的键集合必须完全一致。语言清单只在脚本的 `LANGUAGES` 写一处（现为 en / zh-Hans / zh-Hant / ja），
加语言时改它并一次补齐该语言的全部键——键集合要求一致，分批合入会让中间版本构建失败。键从两处取：SwiftUI 的 `Text` / `Label` / `Section` / `String(localized:)`
读 swiftc 在 `SWIFT_EMIT_LOC_STRINGS: YES` 下写出的 `.stringsdata`；`NSLocalizedString` swiftc 不提取，
从源码取第一个字面量参数。

- 闸门看不到的一类：字面量先放进 `String`，再交给 `Text(someString)`、`.accessibilityValue(someString)`——
  SwiftUI 逐字显示、不查表。这类要在源头写成 `NSLocalizedString(...)`，写对了就自动进入闸门视野。
- 上线当天已缺翻译的键登记在 `scripts/localization-missing-baseline.txt`，只许收敛：补上翻译后删掉那一行，
  新写的文案直接各语言补齐，不登记。基线里某个键已经各语言齐全却没删，闸门同样失败。

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

声明文件里另有两种形态：`multi-scale-png`（1x / 2x / 3x 三档，用于按 pt 尺寸原生渲染、不经缩放的图，例如底栏图标）
与 `keep-as-is`（维持现状）。形态取值的定义写在声明文件头部。

形态怎么选有实测依据（逐项数据只存于历史审计报告，不作合同依据）：占位图一律被缩放到版面框，多档槽位无收益；
渲染宽度远小于原生分辨率的图标 lossy 后在真实渲染宽度上的 SSIM 仍有 0.990 以上，
而按接近原生分辨率铺满屏幕的图（视频详情占位图）只剩 0.964，因此保持无损。

运行期那一半由 `BrowseCraftTests/Shared/Resources/BundledImageAssetTests.swift` 把关：它读同一份声明，
验证编译进 App 之后每张资产还能解出 `CGImage` 且尺寸与声明一致：单档资产比像素，`multi-scale-png` 比 pt——
它的声明列写的是 @1x 像素，运行期按设备 scale 取 @2x / @3x 那一档。两处共用一份声明，不会互相漂移。

## illustration-cutout.swift / illustration-banner.swift / illustration-despeckle.swift

即梦插画入库前的处理，产物再按上一节登记进 `bundled-image-asset-budgets.txt`。都是本机手动工具，不进构建、不进闸门。

```bash
# 空状态：Vision 前景蒙版抠成透明底、裁掉透明边、缩到 540px 高（按 180pt 显示）
swift scripts/illustration-cutout.swift <原图> <输出.png> 540
# 发丝外沿留了白底（深色底下是一条白边）时加第 4 个参数：从透明处向相连的近白像素洪水填充清掉
swift scripts/illustration-cutout.swift <原图> <输出.png> 540 236

# 类型横幅：整张缩到 336px 高靠右放，左侧用原图左缘平均色补齐并渐变过渡，得 1200×336；
# 物件离右缘不足一成时用第 6 个参数整体左移（右侧同样补齐）
swift scripts/illustration-banner.swift <原图> <输出.png> 1200 336 140 [右侧留白px]

# 去噪点：抠图后清掉与主体不相连的小色块（面积 < 200px），再裁掉左右透明边；高度不变。
# 画面里故意画的火花、光点用第 4 个参数圈出保留区域（像素坐标，左上为原点）
swift scripts/illustration-despeckle.swift <抠图结果.png> <输出.png> 200 [x0,y0,x1,y1]
```

抠图把所有前景实例一起保留，但与人物离得远的悬浮小物件（钥匙、卡片）可能被当成背景去掉，画在白背景上的光点也会一起去掉；
入库前把结果叠在深色底上看一眼。

## check-ad-configuration.sh

Runs as a pre-build phase of the `BrowseCraft` target. A PROD archive
(`ACTION=install`) that still uses Google's sample rewarded ad unit fails; every
other build only prints a warning. A PROD archive also asserts that the catalog
decryption key list (`BROWSECRAFT_CATALOG_ENCRYPTION_KEYS`) is non-empty and contains a
`prod-` key (`BCA-BUILD-003`); Debug and TestFlight may keep the tracked test key. Debug, TestFlight and Release all carry the
real rewarded ad unit in `project.yml`, so it currently reports clean everywhere.

```sh
BROWSECRAFT_ENVIRONMENT_NAME=PROD ACTION=install ./scripts/check-ad-configuration.sh
```

## check-docs.py

文档闸门。执行 [`docs/README.md`](../docs/README.md) 第 3–5 节定义的形态与条款规则；它只执行，不定义。
改动 C 类文档、`docs/STATUS.md` 或 `AGENTS.md` 后，提交前跑一次（`BCA-DOC-010`）。

```sh
python3 scripts/check-docs.py
```

十三项检查：A1 定义点唯一、域在受控词表内、H 类归档不承载定义点；A2 引用到的 ID 都有定义点
（`BCA-*` 查本仓库，`BC-*` 与 `APP-MEMO-*` 查 fwq 的 C 类，后者的定义点在 fwq `docs/rules/app-memos.md`）；A3 本仓库的 C 类不为 fwq 已定义的 ID 另写定义点；A4 C 类无状态串头部行；
A5 C 类无 commit 哈希与测试计数；A6 C 类无带日期的章节标题；A7 链接可解析、无绝对主机路径；
A8 `docs/STATUS.md` 每格落枚举或形态；A9 根 `HANDOFF.md` 只承载四样东西（行数与 commit 哈希数是信号，
阈值的唯一声明点在脚本里，文档不复述数值）；A10 文档点名的类型必须在源码里存在（`BCA-DOC-014`）；A11 承载定义点的文档必须被 git 跟踪（`BCA-DOC-015`）——
不被跟踪的文档（如 `.gitignore` 掉的 `AGENTS.md`）只能写引用点，条款正文放进去等于那条合同不在仓库里；
A12 `docs/STATUS.md` 里整节到终态且超期的节（`BCA-DOC-016`；终态含 `optional` / `rejected` 决策与 `superseded` 设计）——**只提示，不判失败**，阈值的唯一声明点在脚本里；
A13 埋点字典、日志类别与崩溃诊断入口（`BCA-OBS-001` / `003` / `004` / `007` / `011`）：`AppAnalytics.Event`、`AppAnalytics.Parameter` 与 `DiagnosticScreen` 的每个 case 带 `///` 注释，
名字与 `docs/design/Analytics-Events-Design.md` 第 3–5 节双向一致；`Domain` / `Application` / `Infrastructure` 不引用 `AppAnalytics`；
业务代码不直接调 `logScreenView`；规则执行失败只经 `RuleFailureDiagnostics.report`，`logDiagnosticFailure` 与
Crashlytics 的记录方法不在别处出现，只有 `CrashDiagnostics` 引入 Crashlytics；BrowseCraftLog 包 `LogCategory` 的每个 case 带 `///` 注释，
与 `docs/design/Logging-Design.md` 第 5 节双向一致；`ProblemReportProblemType` 的原始值与 `docs/design/Problem-Report-Design.md` 第五节的问题码表双向一致（`BCA-OBS-018`，不逐 case 要求注释）。

围栏代码块在 A1、A4–A7、A9 与 A10 前一律剥掉——里面的 ID 是语法示例、哈希是命令输出、`[](…)` 不会被渲染成链接。
A2 与 A3 要读 fwq 仓库（缺省同级目录 `../fwq`，用 `--fwq` 改），A10 与 A13 的日志类别要读五个兄弟包的源码；
**这些仓库不可达时对应检查跳过并如实报告跳过，不静默通过**。本地没有 `AGENTS.md`（它被 `.gitignore`）时同样跳过并报告（A0），不抛错。
扫描集含五个兄弟包的根 `README.md`——端点清单、依赖陈述只有它们承载，不扫就漏。

A10 的语料含 App 与五个包的 `Sources/`、`Tests/`、`Package.swift`、`project.yml`，外加仓库树的
目录名与文件名——文档引用 `TestDoubles/`、`UseCases/` 这类路径段是合法的。反引号内以 `*` 开头的
记号按家族通配处理：源码里有任一以它结尾的符号即成立（`*PersistenceCoordinator` 实有 9 个）。
外部符号白名单在 `scripts/docs-external-symbols.txt`。它不接进 pre-build 阶段：文档闸门失败不应阻断代码 build。
