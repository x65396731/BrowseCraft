# HANDOFF —— 会话入口

> 本文是**会话入口**，属 H 类（`BCA-DOC-011`）。它只承载四样东西：当前状态的现查口径、未选候选与挂账的指针、
> 环境与命令速查、归档索引。判据全部在 C 类文档（入口 [`docs/README.md`](docs/README.md)），瞬时状态全部在
> [`docs/STATUS.md`](docs/STATUS.md)。任何状态性数字（提交、推送、测试数、条款数、警告数）**在复述前必须现查，不得照抄本文**。
>
> **分工**：本文只记纯 App 侧的工作。由规则生成引出的 App 改动（`APP-MEMO-*`）流水在 fwq 仓库的 `HANDOFF.md`，这边只留指针。
>
> **发到频道时**只贴第 1 节的表格，前面加一句现状、后面加一句下一步；第 2 节不贴。

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
`验证` 列三级不可互相推断：`full-suite-passed` 是离线测试全过，`simulator-passed` 是模拟器走通流程，
`device-passed` 是用户真机确认。模拟器通过不等于真机通过。

## 1. 挂账（指针，不复述）

挑活前按 `docs/STATUS.md` 第 0 节的三步核对，不要只看名字就开工。每页的真机验收看点在各自合同末尾的「真机验收清单」一节，
读代码要点在合同的「实现位置」或「读代码要点」一节；本表只说欠什么。

| 挂账 | 欠什么 | 合同 | STATUS |
| --- | --- | --- | --- |
| 删除来源连带删除历史与收藏 | 真机 | [Source-Deletion-Cascade](docs/design/Source-Deletion-Cascade-Design.md) 第七、八节 | 第 4 节两行 |
| 续看位置同步到 iCloud | 两台设备对测（同一 iCloud 账户、同一种安装方式、同一个来源；书的 `locatorJSON` 跨设备可用性未实测）+ 真机退后台的时间够不够 | [History-Resume-Sync](docs/design/History-Resume-Sync-Design.md) 第三、五节 | 第 4 节两行 |
| 17 页重设计：来源、收藏、规则目录、历史、设置、coin 记录、缓存、云同步、添加来源、网址输入与引导屏、库页三种、详情三种、来源内搜索 | 真机验收（含深色）；各页清单列了模拟器没走到的状态 | 各页合同末节 | 第 2 节 |
| 规则目录：「我的生成」优先落段；删失败记录整入口软删除 | 任何验证 | [Catalog-Page-Redesign](docs/design/Catalog-Page-Redesign-Design.md) 第 2.1 / 2.3 节 | 第 2 节末两行 |
| F2-5 / F2-6：进列表先读后写、读书线读库经 actor | 验证 | — | 第 6 节 |
| 漫画详情分段芯片锚点（2026-10-10 已改为按分区头高度换算） | 模拟器或真机看一眼段首不被盖住；章节 `order` 接线已裁定记账、不做 | [Comic-Detail](docs/design/Comic-Detail-Page-Redesign-Design.md) 第十四节、[Book-Detail](docs/design/Book-Detail-Page-Redesign-Design.md) 第十三节 | 第 2 节 |
| 2026-10-10 复审第十一批（两件裁定）：库页翻页失败走分页脚、目录单条规则解不开逐条跳过（App 与测试目标构建 0 警告，BrowseCraftTests 578 + 84 例全过） | 真机：库页翻到底遇站点出错看分页脚文案与再次触底重试 | [Library-Video](docs/design/Library-Video-Page-Redesign-Design.md) 第七节、[Book-Kind-Wiring](docs/design/Book-Kind-Wiring-Design.md) `BCA-RUNTIME-004` | 第 8 节末两行 |
| 2026-10-10 复审第十批（B-10）：共享图片内存缓存上限 256 MB、单张 20%（App 与测试目标构建 0 警告，BrowseCraftTests 574 + 84 例全过） | 真机：Instruments 看长条漫画连读 100 页的驻留是否在 256 MB 附近封顶、往回翻页有没有变卡（模拟器量不到驻留） | [Cache-Page](docs/design/Cache-Page-Redesign-Design.md) 第二节 | 第 8 节末行 |
| 2026-10-10 复审第九批：`BCA-DB-003` 给 v7 到 v9 补上一版库升级用例（三条；App 与测试目标构建 0 警告，BrowseCraftTests 573 + 84 例全过） | 无欠账 | [Database README](BrowseCraft/Infrastructure/Database/README.md) `BCA-DB-003` | 第 8 节末行 |
| 2026-10-10 复审第七批（跨页复制第一组）：横幅三套收成 `LibraryStateBanner`、时刻写法收成 `LibraryHistoryTimeText`、横幅词条改 `library_banner_*`（App 构建 0 警告、BrowseCraftTests 570 + 84 例全过、五道闸门干净） | 真机：书详情 / 搜索页失败横幅的「登录」「重试」、漫画详情受限横幅、三处继续卡片与瓷砖时刻一致 | [Book-Detail](docs/design/Book-Detail-Page-Redesign-Design.md) 第七节、[Comic-Detail](docs/design/Comic-Detail-Page-Redesign-Design.md) 第八节、[Search](docs/design/Search-Page-Redesign-Design.md) 第五节 | 第 8 节末行 |
| 2026-10-10 复审第六批（B-4）：目录跟随先比指纹、批量一个写事务、不再经 addCatalogSource；v10 迁移 | 真机：打开规则目录页的耗时、回前台静默跟随不切标签 | [Catalog-Rule-Update](docs/design/Catalog-Rule-Update-Design.md) 第二节 | 第 8 节末行 |
| 2026-10-10 复审第五批：Domain 包瘦身（四组类型搬回 App）与 B-6 到 B-8 计算属性改存储 | 真机：影视详情 500 集单线路页滚动、历史页 1000 条切筛选 | [architecture.md](docs/architecture.md) 第 2 节 domain kernel | 第 8 节末行 |
| 2026-10-10 复审第四批（架构清理）：`@unchecked Sendable` 30 → 16、`try!` 豁免归零、`CoinLedgerViewModel` 归位、architecture.md 与 Core 依赖图回写 | 无欠账 | [architecture.md](docs/architecture.md) 第 4 节 | 第 8 节末行 |
| 2026-10-10 复审第三批：七处正则绕过缓存、阅读页请求按身份构造一次（Core / Runtime 各有一笔未提交） | 真机：长目录漫画详情切正倒序、阅读页翻页流畅度 | [STATUS 第 8 节](docs/STATUS.md) 末行 | 第 8 节 |
| 2026-10-10 复审第二批：历史 / 库页按来源与按作品查询、三个详情页收藏与书详情进度经 actor、页面缺口与 11 条裸英文、两份包内 README | 真机：历史页与库页进页耗时、三个详情页收藏切换 | [STATUS 第 8 节](docs/STATUS.md) 末三行 | 第 8 节 |
| 2026-10-10 代码复审八条裁定的实施：云同步 Portal 门禁与旧本地 UUID 覆盖、缩略图缓存键、详情刷新失败横幅、搜索页三处、死代码删除 | 真机：未登录进云同步页看开关禁用与说明、登录后开同步看 `former-local-identity-replaced` 日志 | [STATUS 第 8 节](docs/STATUS.md) 指向的复审报告 | 第 8 节五行 |
| 站点按状态码拒绝不再报成「规则解析出错」（`BCA-RUNTIME-007`，2026-10-10） | 真机找一个回 403 的来源看提示文案 | [RuleExecutionSemantics](docs/design/RuleExecutionSemantics.md) 第三节 | 第 3 节 |
| POST 搜索与非 UTF-8 关键词（fwq `APP-MEMO-031`，Core 与 Runtime 已推送） | 真机：fwq 三站搜索复测通过后，从 App 重交 piaotia 搜「剑帝」 | fwq `BC-SEARCH-022` | fwq STATUS |
| 站点有声播放器后续：界面样式、倍速入口、`mediaAPI` 无语料 | 立项 | [Book-Kind-Wiring](docs/design/Book-Kind-Wiring-Design.md) 第十六节 | 第 1 节 optional 行 |
| 给 fwq 的六条读书 kind 生成需求 | 需求一 / 三 / 四 / 五前半 fwq 已交付并真机通过（小說狂人最新章节 10-10 再修、待部署）；需求二记账、两端都不做；五后半目录分页 fwq 未定立场；六 fwq 不做 | Claude 文档「读书 kind 规则生成覆盖需求」（https://claude.ai/artifact/HnYM71goMZveUVJQQ4vhgk） | fwq STATUS |

下一会话建议顺序：Features 层 85 处颜色绕过 `CatalogStyle`（先在 `CatalogPalette` 加 `onAction` / `separator` / `shadow` / `pressedFill` / `tileTrack`，按目录分批）→ 跨页复制其余各组 → 真机验收；APIKit 仓删零引用的 `PortalCatalogAPI`→ 续看同步两机对测 → 真机验收（用户在真机上走，结果新增 `device-passed` 行、不改模拟器那几行）。

- **fwq 侧指针**（定义点与验证状态都在 fwq `docs/rules/STATUS.md`）：`BCA-RUNTIME-005`（fwq `APP-MEMO-026`）里「直接请求收到挑战页回退 WebView」一处仍欠真机，
  发版后由用户重交 toonily 验证，发版前 Cloudflare 站不要重生成；`BC-PREFLIGHT-066`（点推送停在原页、打开目录直接看到新规则）在 fwq 为 `not-run`，随规则目录页真机一起看；
  `BC-EVIDENCE-082` 与「选集无线路名标线路 N」在影视详情页清单里。真机结果记回 fwq STATUS 对应行（fwq 没有 `device-passed`，用 `fresh-passed` 并在流水写明是真机）。
- **设计新页面**：先读 Claude 文档「BrowseCraft 页面设计索引」（https://claude.ai/code/artifact/5c5f0bd7-543e-40af-bb70-b5c3f9d1edaf），
  开工时把新页面加进它的页面表，完成后更新那一行。颜色只在 `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift` 一处取值；
  底栏可见性只能挂在 `NavigationStack` 根页的规则见 [Coin-Ledger](docs/design/Coin-Ledger-Page-Redesign-Design.md) 第二节。
- **明确不做**：`决策 = rejected` 的 STATUS 行按名字跳过，不是待办。
- **遗留小项**：本机同步队列里 `local.default` 作用域下有几条早先留下的来源删除与收藏待传项，未处理。

## 2. 环境与命令速查

五个仓库是**同级 checkout 的 path 依赖**，没有版本 tag；App 的 `main` 只对得上兄弟仓的 `main`：

```
~/Desktop/
  BrowseCraft/            # App
  BrowseCraftCore/  BrowseCraftDomain/  BrowseCraftRuntime/  BrowseCraftAPIKit/
  SwiftSoup/              # 自家 fork，整张依赖图的本地覆盖（BCA-BUILD-002）
  fwq/                    # 规则生成引擎，BC-* 与 APP-MEMO-* 的定义点在这里
```

工具链：`xcodegen` 只保留 `/opt/homebrew` 下的 arm64 版；Homebrew 从源码编译要求独立的 Command Line Tools 与 Xcode 同版本。

```bash
# 工程文件不同步时先重新生成（BCA-BUILD-001）；纯文档改动不需要。
scripts/regenerate-project.sh

# 四个代码闸门（pre-build）+ 本地化闸门（编译后，单独跑要传 Objects-normal 目录）+ 文档闸门
scripts/check-architecture-boundaries.sh     # BCA-ARCH-001 ~ 005
scripts/check-swiftsoup-override.sh          # BCA-BUILD-002
scripts/check-ad-configuration.sh            # BCA-BUILD-003
scripts/check-bundled-image-assets.sh        # BCA-BUILD-006 ~ 007
scripts/check-localization.py <Objects-normal 目录>
python3 scripts/check-docs.py                # BCA-DOC-010；fwq 不在 ~/Desktop/fwq 时加 --fwq <路径>

# build 与测试（AGENTS.md：只有用户明确要求时才跑）。destination 写「OS + 名字」，不写 UDID；
# 运行时用 iOS 26 及以上（iOS 18.5 跑不了测试）。
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' build
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' test -only-testing:BrowseCraftTests

# 包各自的测试
for d in BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit; do
  (cd ~/Desktop/$d && swift test)
done
```

- **scheme 与工程文件**：三个 scheme 的归档目标与广告单元检查见 `docs/architecture.md` 第 3 节 `BCA-BUILD-003`；
  `project.pbxproj` 是生成的且已 git-ignore，在 Xcode 里改的设置会被下次 `regenerate-project.sh` 冲掉（`BCA-BUILD-004`）。
- **模拟器走查**：用户指定 iPhone 18 Pro（iOS 27.0），已登录真实账号、云同步开（Development 环境）；库里现有哪些来源现查。
  系统开关点不动要横向拖；数据库在 App 容器的 `Library/Application Support/BrowseCraft/`，重装后容器路径会变，用 `find` 现找；
  启动的开场视频点右下「跳过」；进阅读器前的广告门等「奖励已发放」后用广告自带的关闭按钮关。面板截图偶尔是旧帧，以 `xcrun simctl io <设备> screenshot` 为准。
  整套测试放另一台 iPhone 17（iOS 26.5）模拟器后台跑，看到 `TEST SUCCEEDED` 即可，`xcodebuild` 进程可能再挂二十多分钟才退出。
- **偶发失败的测试**：`ReadinessSelectorContentSemanticsTests.testWeakSelectorReturnsBeforeTheContentArrives` 是 WebView 就绪的计时断言（上限 1300 ms），
  整套跑时偶红、单独重跑通过；看到它红先单独重跑再下结论。
- **iCloud 环境**：Xcode 直接安装的包连 Development，TestFlight 与商店的包连 Production，两边数据不通；改了云端字段，发 TestFlight 之前先在控制台「Deploy Schema Changes」。
  细节与同步日志的判据见 [History-Resume-Sync](docs/design/History-Resume-Sync-Design.md) 第五节。
- **插画入库**：即梦出图 → 抠图 → 去游离小点 → 登记预算，三个脚本的用法见 [`scripts/README.md`](scripts/README.md)。

## 3. 归档索引

`docs/history/` 是只读归档（`BCA-DOC-009`）：不构成生产约束，不参与逐条核对，不得被引用为实施依据。
**归档里的「下一步」「待补」清单一律按当时的判断看待，不得照着开工**——先查 `docs/STATUS.md` 对应行。
归档清单与各卷内容在 [`docs/README.md`](docs/README.md) 第 7 节，不在此重复；当前有效的规范与设计在同文第 6 节按任务列出。
