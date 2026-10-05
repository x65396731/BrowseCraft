# HANDOFF —— 会话入口

> 本文是**会话入口**，属 H 类（`BCA-DOC-011`）。它只承载四样东西：当前状态的现查口径、
> 未选候选与挂账的指针、环境与命令速查、归档索引。
>
> 它**不承载条款定义点，也不复述定义点正文**——判据全部在 C 类文档（入口 [`docs/README.md`](docs/README.md)），
> 瞬时状态全部在 [`docs/STATUS.md`](docs/STATUS.md)。
>
> 任何状态性数字（提交、推送、测试数、条款数、警告数）**在复述前必须现查，不得照抄本文**。
> 本文刻意不记这些数字，只记怎么查。
>
> **分工**：本文只记**纯 App 侧的工作**——分层与边界、构建与警告、Readium 与 book 接线、
> 资产与性能、文档架构。由规则生成引出的 App 改动（`APP-MEMO-*`）流水在 fwq 仓库的 `HANDOFF.md`，
> 这边只留指针，同一件事不写两份。

## 0. 当前状态（现查口径）

```bash
# 五仓 + SwiftSoup fork 的 HEAD、是否干净、是否有未推送
for d in BrowseCraft BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit SwiftSoup; do
  printf '%-22s ' "$d"
  git -C ~/Desktop/$d log --oneline -1
  printf '%-22s   未提交 %s 处，未推送 %s 个\n' '' \
    "$(git -C ~/Desktop/$d status --porcelain | wc -l | tr -d ' ')" \
    "$(git -C ~/Desktop/$d log --oneline @{u}.. 2>/dev/null | wc -l | tr -d ' ')"
done

# 文档闸门（改过 C 类文档 / STATUS / AGENTS 就跑，BCA-DOC-010）
python3 scripts/check-docs.py
```

各工作项的决策 / 设计 / 实施 / 验证状态见 [`docs/STATUS.md`](docs/STATUS.md)，一行一项，每格一个枚举值。
**`验证` 列的三级不可互相推断**：`full-suite-passed` 是离线测试全过，`simulator-passed` 是模拟器走通流程，
`device-passed` 是用户真机确认。模拟器通过不等于真机通过。

## 1. 未选候选与挂账（指针，不复述）

以下都在 `docs/STATUS.md` 里有行；挑活前按该文件第 0 节的三步核对，不要只看名字就开工。

**`required` 里验证还没走完的有两条：删除来源连带删除历史与收藏（只欠真机）；续看位置同步到 iCloud（单机已过，欠两台设备对测与真机）。
其余 `required` 是九页重设计，共同欠真机验收。下一会话优先做下一步三的对测，真机验收等用户在真机上走。**

- **下一步一：删除来源连带删除的真机验收**。合同：[`Source-Deletion-Cascade-Design.md`](docs/design/Source-Deletion-Cascade-Design.md)
  （第六节实现位置、第七节测试与验收）与数据库说明「Source 删除规则」（`BCA-DB-004`、`BCA-DB-005`）；STATUS 在第 4 节两行（`full-suite-passed` 与 `simulator-passed`），
  改了什么、测试与走查怎么做的见 `docs/history/status-log.md` 2026-10-03 最后三节。剩下的验证：
  真机按第 54 行起的来源页条目验收（实施提交 c2b2437）。读代码时要知道的几点：
  - 删除的留底是 `SourceDeletionReceipt`（`SourceRepository.swift`）；删除路径不再在事务后发同步通知，由 `SourcesViewModel.finishUndoableDeletion`
    在撤销窗口结束（4 秒超时、被新删除替换、离开来源页、App 切走）时经 `SourcesPersistenceCoordinator.notifyDeletionChanges` 补发；
    撤销不发删除的通知，`restoreDeletedSource` 写回后自己通知。
  - 只有用户在来源页删一个来源可撤销；删除「我的生成」规则与个人规则过期走 `deleteSourcesWithoutUndo`，删完立刻通知。按下标批量删多个也不给撤销。
  - 撤销时仓储把删除前的库状态（含列表位置）原样写回，ViewModel 改回当前来源时不再覆盖库状态；库页切换来源本来就会重置分段，
    所以列表位置只在下次启动恢复时体现——这是已知出入，不是 bug。
  - 解不出配置的来源照样删（历史与收藏一并删），只是拿不到留底、不能撤销。

来源页、收藏页、规则目录页、历史页、设置页、coin 记录页、缓存页、云同步页、添加来源页九页重设计都已实施，离线测试与模拟器走查通过，共同欠真机验收。
设置页的子页已全部按新样式做完；添加来源之后的引导屏与网址输入页仍是系统表单，各自另立项、输入页优先；库页仍未立项，等用户点名。

- **下一步二：九页真机验收**（用户在真机上走，结果记回 `docs/STATUS.md` 第 2 节，新增 `device-passed` 行，不改模拟器那几行）：
  - 来源页：点其他来源切换成功后跳库、失败留在原页；「更多位置」切到设置页并打开购买页；正在使用的深色瓷砖与类型色；
    已暂停一组与启用窗口；长按菜单与左滑删除（删除色 `#E5484D`，不弹确认；连带删除做完后确认历史与收藏一并消失、撤销后都回来）。
  - 收藏页：「全部 | 视频 | 漫画 | 书籍」一直显示、某类为 0 的小空状态；按天分组；左滑与长按取消收藏不弹确认、底部撤销按原日期恢复；
    「在库中查看来源」；已暂停 / 已删除 / 未知来源三种行；取消后库页爱心同步。
  - 规则目录页：**第一次打开**（目录还没加载完）时标题与分段控件不再向左溢出——这是 2026-10-03 用户真机发现、已修的问题，
    只在加载骨架出现时触发，冷启动后直接打开目录最容易看到；浅色模式与六张插画观感。
    顺带做 fwq `BC-PREFLIGHT-066`：生成一条规则 → 点推送应停在原页不跳转 → 打开目录应直接看到新规则、不用下拉。
  - 历史页：继续卡片三种色块与「上次看到 / 上次读到」、视频进度条与「已看完」、左滑与长按删除及撤销（漫画删一行后上一章不再冒出来、撤销回到原日期分组）、
    在库中查看来源、点已暂停来源的行打开启用窗口、空状态；收藏页同一批封面与撤销提示条已改为共用组件，顺带回归。
  - 设置页：已登录账号卡的余额、「看广告 +N」看完后余额变化、「coin 记录 ›」；未登录卡的插画 `SettingsSignIn`、系统 Apple 登录按钮、
    不计奖励的看广告；诊断码与账号 ID 点一下复制；退出登录弹居中确认框（取消 / 红色退出登录）；「高级版」打开购买页且底栏隐藏。
  - coin 记录页：进入后底栏隐藏只留返回、返回后底栏恢复；余额卡与价格说明；按天分组翻页到底；获得色绿；加载失败与没有记录两种状态（模拟器没触发到）。
  - 缓存页：进入后底栏隐藏；用量卡与「最多」合计；改上限后合计跟着变；清除后用量归零、显示释放多少，来源登录状态不受影响。
  - 库页 / 播放顺带看两条 fwq 项：片源 403 的作品应提示换片源而不是整页兜底（`BC-EVIDENCE-082`）；选集无线路名的站应按重复集号分「线路 1 / 2」。
  - 云同步页（合同 [`Cloud-Sync-Page-Redesign-Design.md`](docs/design/Cloud-Sync-Page-Redesign-Design.md)）：进入后底栏隐藏；
    状态卡各状态（未开启、正在检查、正在同步、已同步）；页面上没有按钮，下拉即同步；首次开启窗口两张入口卡；「同步的内容」三行的条数。
    模拟器没看到的三样真机顺带看：未登录 iCloud 的状态卡、同步出错卡下面的小字技术文字、首次开启窗口的提交中状态。
  - 添加来源页（合同 [`Add-Source-Page-Redesign-Design.md`](docs/design/Add-Source-Page-Redesign-Design.md)）：来源页「＋ 添加」弹出；三张类型横幅与目录页同一批插画；
    「接下来」三行与 coin 一行（价格取服务端普通档）；点「从规则目录挑一个」本页先收起再弹目录；点类型卡在同一层 sheet 里进引导屏或输入页，不叠第二层；输入页「关闭」回来源页。
    模拟器没走到的三样真机顺带看：未登录时 coin 一行换成警示色「提交生成需要登录」；余额还没同步到时只写价格；从目录「我的生成」空状态进入时没有目录入口卡。
  - 九页都要在深色模式下各看一遍；iCloud 首次恢复失败的下拉重试在真机上不易触发，可不强求。
- **下一步三：续看位置同步的两台设备对测**。合同 [`History-Resume-Sync-Design.md`](docs/design/History-Resume-Sync-Design.md)，
  STATUS 第 4 节两行（`full-suite-passed` 与 `simulator-passed`），做了什么与没做什么见 `docs/history/status-log.md` 2026-10-04 最后几节。
  已验证的只有单机：退到后台触发同步、上传、删除标记、云同步页条数。**没验证的**：
  - 另一台设备下载后写入历史、点进去回到原位置——真实 iCloud 上一次都没跑过，只有测试替身覆盖。
    对测要两台设备登录同一 iCloud 账户、用同一种安装方式、且都有同一个来源。
  - 有实际进度的内容：漫画页码、视频秒数、书的阅读位置。书的 `locatorJSON` 跨设备能否直接用没有实测，不行就退回「章节地址 + 进度」。
  - 真机上退到后台时系统给的时间够不够跑完（不要挂着 Xcode 调试器测）。看日志的命令与判断标准：
    `xcrun simctl spawn booted log stream --predicate 'process == "AnyPortal" AND category == "CloudSync"'`，
    退到后台后应有 `sync started trigger=localChange` 与随后的 `sync completed`。
  读代码时要知道的几点：
  - 三个历史仓储与删除来源的连带路径都**没有**改。本机改动靠每轮同步时拿历史表对比账本表 `history_sync_ledger` 找出来
    （`GRDBHistoryEntrySyncLocalStore.registerLocalChanges`）：没有账本行是新增，行时间更晚是改动，账本活着而行没了是删除，账本已删而行又有了是恢复。
  - 来源不在本机（已删除或不属于当前数据空间）的历史不上传，指向这种来源的云端记录也不写入；同一轮同步里来源先于历史下载。
  - 历史写入本身不触发同步；触发靠原有时机加「退到后台时同步一次」（`AppContainer.handleAppEnteredBackground`）。
  - 与设计书的出入已写进合同：发现改动的方式、「只用 iCloud 数据」时不做特殊处理、视频没有单独的上传时机。
- **iCloud 环境与 CloudKit 控制台**（合同第五节）：Xcode 直接安装的包连 Development，TestFlight 与商店的包连 Production，
  与工程里的环境名 TEST / PROD 无关，两边数据不通。改了云端字段，发 TestFlight 之前必须先在控制台「Deploy Schema Changes」。
  现状：两个环境的 `Source`（12 个字段，含 `origin`）、`FavoriteItem`（13）、`AppUserIdentity`（4）、`HistoryEntry`（21）已一致，
  当前不欠部署。控制台要用户自己登录；用内置浏览器加字段时表单只能一个个填，字段名打进去后用页面文字核对，不要信截图。
- **待确认的小项**：`project.yml` 给 `Info.plist` 预处理加了 `-Wno-unicode-homoglyph`（全角标点被报成四条警告），改后没有 build 验证，
  下次编译时看警告是否消失。本机同步队列里有 `local.default` 作用域下的 4 条来源删除与 3 条收藏待传项，是早先留下的，未处理。
- **合同与走查记录**：来源页 [`Sources-Page-Redesign-Design.md`](docs/design/Sources-Page-Redesign-Design.md)、
  收藏页 [`Favorites-Page-Redesign-Design.md`](docs/design/Favorites-Page-Redesign-Design.md)、
  规则目录页 [`Catalog-Page-Redesign-Design.md`](docs/design/Catalog-Page-Redesign-Design.md)、
  历史页 [`History-Page-Redesign-Design.md`](docs/design/History-Page-Redesign-Design.md)、
  设置页 [`Settings-Page-Redesign-Design.md`](docs/design/Settings-Page-Redesign-Design.md)、
  coin 记录页 [`Coin-Ledger-Page-Redesign-Design.md`](docs/design/Coin-Ledger-Page-Redesign-Design.md)、
  缓存页 [`Cache-Page-Redesign-Design.md`](docs/design/Cache-Page-Redesign-Design.md)、
  云同步页 [`Cloud-Sync-Page-Redesign-Design.md`](docs/design/Cloud-Sync-Page-Redesign-Design.md)、
  添加来源页 [`Add-Source-Page-Redesign-Design.md`](docs/design/Add-Source-Page-Redesign-Design.md)，设计稿画布与设计文档链接都在各自开头；
  模拟器走查的方法、临时注入与结果记在 `docs/history/status-log.md` 对应日期一节，注入都已撤回、未提交。
  与设计稿的已知出入：来源页已暂停一组没有虚线外框、启用窗口里启用后不跳库；iOS 26 / 27 上左滑按钮是系统圆形样式。
- **新页面设计的入口**：Claude 文档「BrowseCraft 页面设计索引」（https://claude.ai/code/artifact/5c5f0bd7-543e-40af-bb70-b5c3f9d1edaf）
  收录已完成各页的合同、画布、颜色与尺寸、可复用组件、交互约定和新页面检查清单。设计任何新页面前先读它，
  开工时先把新页面加进它的页面表，完成后更新那一行。用户裁定：页面之间主题色不能差异过大；颜色只有
  `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift` 一处取值；删除色 `#E5484D`；获得色绿（`CatalogPalette.gain`）。
  推入的二级页隐藏底栏只留返回；标签页若要控制底栏，只能挂在 `NavigationStack` 里的根页上、平时取 `.automatic`
  （挂在栈外或写显式 `.visible` 会盖过二级页的隐藏，设置页为此改过一次）。
- **模拟器走查环境**：用户指定 iPhone 18 Pro（iOS 27.0）模拟器，已登录真实账号，可直接看已登录态。该账号的云同步是开启的（Development 环境），
  现有 1 个来源「樱花动漫 · 日本动漫」（10-04 走查时加的，占满唯一的来源位置），所以 App 打开直接进库页。
  模拟器面板点不动系统开关，要在开关上横向拖；数据库在 App 容器的 `Library/Application Support/BrowseCraft/`，重装后容器路径会变，用 `find` 现找。启动有一段开场视频，点右下「跳过」。整套测试放在另一台 iPhone 17（iOS 26.5）
  模拟器上后台跑，互不干扰；测试两分钟内跑完，但 `xcodebuild` 进程可能再挂二十多分钟才退出，看输出里的 `TEST SUCCEEDED` 即可。模拟器面板的截图偶尔是旧帧，以 `xcrun simctl io <设备> screenshot` 为准。
- **插画**：空状态插画都是即梦出图 → `scripts/illustration-cutout.swift` 抠图 → `scripts/illustration-despeckle.swift` 去游离小点
  → 登记 `scripts/bundled-image-asset-budgets.txt`。已有插画的游离小点已清；人物轮廓上的浅色毛边是白底抠图留下的，未处理（optional）。
- **偶发失败的测试**：`ReadinessSelectorContentSemanticsTests.testWeakSelectorReturnsBeforeTheContentArrives` 是 WebView 就绪的计时断言
  （上限 1300 ms），2026-10-03 整套跑时测得 1523 ms 失败、单独重跑通过；整套测试看到它红时先单独重跑再下结论。

剩下的全是 `optional` 或已裁决不做。

- **无语料、等样本**：读书 kind 的四个接口变体（list / detail / reader 的 API 形态）。
- **由规则生成引出的 App 侧改动，定义点与验证状态都在 fwq `docs/rules/STATUS.md`**（不再指向 fwq `HANDOFF.md` 第 1 节——那一节已翻到后面的轮次）：
  `BC-PREFLIGHT-066`（点推送停在原页、生成后打开目录直接看到新规则）在 fwq 为 `not-run`，是唯一什么验证都没跑的，已并进上面「下一步二」的规则目录页条目；
  `BC-EVIDENCE-082`（片源拒绝不走兜底、提示换片源）与「选集无线路名时标线路 N」为 `fresh-passed`，真机顺带看；`BC-PREFLIGHT-067`（懒加载封面，改在 Core）已 `regression-passed`，不必再看。
  真机结果记回 fwq STATUS 对应行（fwq 的验证枚举没有 `device-passed`，用 `fresh-passed` 并在其状态流水写明是真机）。
  同期的纯 App 侧改动（DEBUG 演示模式补足正文并且不弹激励广告、影视详情头图占位换图）不属规则生成，fwq 不记。
  Release 激励广告单元与 AdMob 商店页关联事项照旧。
- **明确不做**（`rejected` / `superseded`，按名字跳过，不是待办）：本地书 B3 有声书播放器、PDF 与 CBZ、
  目录刷新时静默覆盖本地规则、jable.tv 播放根因（已由 fwq `BC-PLAYBACK-049` 承接）、
  CloudKit 门禁的字面量全面扫描（有意收窄，见 `BCA-SYNC-008`）、iOS 18.5 模拟器运行时、
  代码审计里四条被测量推翻的条目（F2-7、F2-10、F3-1、F3-2 与封面请求重复构造）、
  F2-3 后半的显式 `ImagePrefetcher` 预取。

## 2. 环境与命令速查

五个仓库是**同级 checkout 的 path 依赖**，没有版本 tag；App 的 `main` 只对得上兄弟仓的 `main`：

```
~/Desktop/
  BrowseCraft/            # App
  BrowseCraftCore/  BrowseCraftDomain/  BrowseCraftRuntime/  BrowseCraftAPIKit/
  SwiftSoup/              # 自家 fork，整张依赖图的本地覆盖（BCA-BUILD-002）
  fwq/                    # 规则生成引擎，BC-* 与 APP-MEMO-* 的定义点在这里
```

工具链要点：`xcodegen` 只保留 `/opt/homebrew` 下的 arm64 版（x86_64 那份已删，它在本机跑不了）；
Homebrew 从源码编译要求独立的 Command Line Tools 与 Xcode 同版本，只装 Xcode.app 不够。

```bash
# 工程文件不同步时先重新生成（BCA-BUILD-001）。project.yml 不引用任何文档路径，
# 所以纯文档改动不需要跑这条。
scripts/regenerate-project.sh

# 四个代码闸门 + 一个本地化闸门 + 一个文档闸门。四个代码闸门都作为 pre-build 阶段跑，
# 本地化闸门在编译之后跑（单独跑要传 Objects-normal 目录）。
scripts/check-architecture-boundaries.sh     # BCA-ARCH-001 ~ 005
scripts/check-swiftsoup-override.sh          # BCA-BUILD-002
scripts/check-ad-configuration.sh            # BCA-BUILD-003
scripts/check-bundled-image-assets.sh        # BCA-BUILD-006 ~ 007
scripts/check-localization.py <Objects-normal 目录>
python3 scripts/check-docs.py                # BCA-DOC-010；fwq 不在 ~/Desktop/fwq 时加 --fwq <路径>

# build 与测试（AGENTS.md：只有用户明确要求时才跑）。destination 按「OS + 名字」指定：
# 不写 UDID（换机器就失效），也不能只写 name——裸 name 解析不到，必须带 OS。
# 运行时用 iOS 26 及以上：iOS 18.5 上测试包加载会缺 libswiftWebKit.dylib（Xcode 27 SDK
# 配旧运行时的错配），build 不受影响但跑不了测试。
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' build
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' test -only-testing:BrowseCraftTests

# 包各自的测试
for d in BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit; do
  (cd ~/Desktop/$d && swift test)
done
```

三个 scheme 的归档目标不同：`TEST BrowseCraft` 归档 `TestFlight` 配置（环境 TEST），
`BrowseCraft` 与 `PROD BrowseCraft` 归档 `Release` 作 PROD，后两者在广告单元还是 Google 示例值时拒绝构建
（`BCA-BUILD-003`）；目前三套配置都已是真实激励广告单元，这道检查不会拦。`project.pbxproj` 是生成的且已 git-ignore，在 Xcode 的 Signing & Capabilities 里改的东西
会被下次 `regenerate-project.sh` 冲掉（`BCA-BUILD-004`）。

## 3. 归档索引

`docs/history/` 是只读归档（`BCA-DOC-009`）：不构成生产约束，不参与逐条核对，不得被引用为实施依据。
**归档里的「下一步」「待补」清单一律按当时的判断看待，不得照着开工**——先查 `docs/STATUS.md` 对应行。

| 归档 | 内容 |
| --- | --- |
| [status-log.md](docs/history/status-log.md) | 状态变更流水：被 `STATUS.md` 覆盖的旧值，与三分法从 C 类搬出的叙事事实 |
| [2026-09-19-docs-architecture-audit.md](docs/history/2026-09-19-docs-architecture-audit.md) | 文档架构审计与 D0–D5 迁移提案，含迁移前的量化基线 |
| [2026-09-18-code-audit.md](docs/history/2026-09-18-code-audit.md) | 五仓代码审计：警告清单、架构、性能热点与逐项修正纪事 |
| [Book-Kind-Wiring-batch-records.md](docs/history/Book-Kind-Wiring-batch-records.md) | 读书 kind 分批落地记录与模拟器 / 真机实测纪事 |
| [RSS-Removal.md](docs/history/RSS-Removal.md) | RSS 从五仓整体下线的执行记录与保留清单 |
| [Readium-Integration-Handoff.md](docs/history/Readium-Integration-Handoff.md) | Readium 选型与 SwiftSoup fork 的来龙去脉 |
| [JablePlaybackRule-Handoff.md](docs/history/JablePlaybackRule-Handoff.md) | jable.tv M3U8 抽取失败的根因交接 |
| [Phase0-Data-Contract-and-Security-Audit.md](docs/history/Phase0-Data-Contract-and-Security-Audit.md) | CloudKit 阶段 0 的数据合同与 payload 安全审计 |

当前有效的规范与设计在 [`docs/README.md`](docs/README.md) 第 6、7 节按任务列出。
