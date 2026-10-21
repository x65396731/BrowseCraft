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
# 六仓的 HEAD、是否干净、是否有未推送（在 App 仓根目录运行；六个仓库是同级 checkout）
for d in BrowseCraft BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit BrowseCraftLog; do
  printf '%-22s ' "$d"
  git -C ../$d log --oneline -1
  printf '%-22s   未提交 %s 处，未推送 %s 个\n' '' \
    "$(git -C ../$d status --porcelain | wc -l | tr -d ' ')" \
    "$(git -C ../$d log --oneline @{u}.. 2>/dev/null | wc -l | tr -d ' ')"
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
| 取用公共规则重试沿用同一 `Idempotency-Key`（服务端 PortalCore 2026-10-21 已收：请求头 `[A-Za-z0-9._:-]{1,128}`，同用户、同网址、同键 24 小时内重发只扣一次、返回同样的 coinCharged） | 网址输入页每次「滑动取用」生成一个键（UUID 即可）、超时重发沿用同一键；不带键的行为不变（再扣一次）。10-21 发布前审计留首发后项② | PortalCore `docs/api/rule-generation.md`「coin」节；审计 https://claude.ai/artifact/EVW1iCtAq44dFangavfyBL | — |
| 活动与生成率提示（`BCA-UI-004` / `BCA-UI-005` / `BCA-SYNC-012`；设计书、画布链接在合同头部） | 真机没看的：成功率一行有数据时的文案（新账号提交生成的次日汇总后才有数）、活动推送点击；服务端未做：活动入账脚本与新记账原因（要迁移，等发活动前再做）；Firebase 控制台「限时活动 · 送 300 coin」是草稿，用户说发再发——先跑入账脚本并报人数，再按活动天数改「首次打开超过 N 天前」、填起止日期后发布 | [Campaign-And-Rate-Notices](docs/design/Campaign-And-Rate-Notices-Design.md) 第五、七、八节 | 第 11 节 |
| 页内问题报告（`BCA-OBS-018` ~ `022`、`BCA-UI-006`；设计书 https://claude.ai/artifact/R1jd8HR8q6hKoSKh1vTjMB） | 第二期（用户 2026-10-20：目前做不了）：合同第九节排查第 4、5 步的查询脚本写在 PortalCore 仓，只做脚本、不做自动告警；线上现有的走查报告写脚本时当样本、统计时排除（编号见 status-log）；只读查线上库：ssh 到服务器后在 PortalCore 目录下 `docker compose exec -T api python -`，脚本里用 `app.platform.config.DB_PATH` 以 `mode=ro` 打开。第一期另欠：漫画详情与站点书详情的模拟器走查（模拟器来源位置 1 / 1）与真机 | [Problem-Report](docs/design/Problem-Report-Design.md) 第九、十一节 | 第 12 节 |
| 依赖大版本升级（用户 2026-10-20 裁定：上架后再做，一次一个，各自跑全量与真机，有问题单独回退；现版本见 Package.resolved） | Firebase → 13（改动面最小，先做）；GoogleMobileAds → 13（删了一批旧 API，激励广告 / SSV / ATT 时序要重验）；GRDB → 7（写事务默认 immediate、Record 方法签名变、Swift 6 并发更严，13 个仓储与云同步落库都压在它上面）；Nuke → 13（管线改全局 actor、回调签名变，封面 / 缩略图 / 阅读页三条管线要过）；KSPlayer → main（播放器核心）。SwiftSoup 已是官方版，Alamofire / Readium / WebUI 已是最新 | 各包 release notes | [第 13 节](docs/STATUS.md#13-全量代码审计2026-10-20)「依赖大版本升级」行 |
| 删除来源时保留历史与收藏（取代连带删除） | 真机 | [Source-Deletion-Cascade](docs/design/Source-Deletion-Cascade-Design.md) 第七、八节 | 第 4 节 targeted-passed 行 |
| 续看位置同步到 iCloud | 两台设备对测（同一 iCloud 账户、同一种安装方式、同一个来源；书的 `locatorJSON` 跨设备可用性未实测）+ 真机退后台的时间够不够 | [History-Resume-Sync](docs/design/History-Resume-Sync-Design.md) 第三、五节 | 第 4 节两行 |
| 19 页重设计：来源、收藏、规则目录、历史、设置、coin 记录、缓存、云同步、添加来源、网址输入与引导屏、库页三种、详情三种、来源内搜索、有声书播放页、删除账号页 | 真机验收（含深色）；模拟器没走到的状态见 STATUS 各页走查行 | 各页合同末节「真机验收清单」 | 第 2 节、第 4 节 |
| 规则目录：「我的生成」优先落段；删失败记录整入口软删除 | 任何验证 | [Catalog-Page-Redesign](docs/design/Catalog-Page-Redesign-Design.md) 第 2.1 / 2.3 节 | 第 2 节末两行 |
| F2-5 / F2-6：进列表先读后写、读书线读库经 actor | 验证 | — | 第 6 节 |
| 漫画详情分段芯片锚点（2026-10-10 已改为按分区头高度换算；2026-10-11 模拟器上书详情同一公式已看过，段首落在分区头下不被盖住） | 漫画详情再看一眼（线上没有漫画来源时跳过）；章节 `order` 接线已裁定记账、不做 | [Comic-Detail](docs/design/Comic-Detail-Page-Redesign-Design.md) 第十四节、[Book-Detail](docs/design/Book-Detail-Page-Redesign-Design.md) 第十三节 | 第 2 节 |
| 代码复审第六～十四批（目录跟随指纹、横幅与时刻写法收敛、v7–v9 升级用例、图片内存缓存上限、翻页失败走分页脚与目录逐条跳过、颜色收回 `CatalogPalette`、跨页复制第二 / 三组） | 真机看点逐批列在 `docs/history/status-log.md`「2026-10-20 第三轮文档复审」节（原八行挂账）；要点：库页翻到底出错看分页脚、长条漫画连读 100 页看驻留、漫画 / 影视详情的共享件与浅深色各看一眼 | STATUS 第 8 节各行点名的合同 | 第 8 节 |
| 2026-10-10 复审第五批：Domain 包瘦身（四组类型搬回 App）与 B-6 到 B-8 计算属性改存储 | 真机：影视详情 500 集单线路页滚动、历史页 1000 条切筛选 | [architecture.md](docs/architecture.md) 第 2 节 domain kernel | 第 8 节末行 |
| 2026-10-10 复审第三批：七处正则绕过缓存、阅读页请求按身份构造一次 | 真机：长目录漫画详情切正倒序、阅读页翻页流畅度 | [STATUS 第 8 节](docs/STATUS.md) 末行 | 第 8 节 |
| 2026-10-10 复审第二批：历史 / 库页按来源与按作品查询、三个详情页收藏与书详情进度经 actor、页面缺口与裸英文词条、两份包内 README | 真机：历史页与库页进页耗时、三个详情页收藏切换 | [STATUS 第 8 节](docs/STATUS.md) 末三行 | 第 8 节 |
| 2026-10-10 代码复审八条裁定的实施：云同步 Portal 门禁与旧本地 UUID 覆盖、缩略图缓存键、详情刷新失败横幅、搜索页三处、死代码删除 | 真机：未登录进云同步页看开关禁用与说明、登录后开同步看 `former-local-identity-replaced` 日志 | [STATUS 第 8 节](docs/STATUS.md) 指向的复审报告 | 第 8 节五行 |
| 站点按状态码拒绝不再报成「规则解析出错」（`BCA-RUNTIME-007`，2026-10-10） | 真机找一个回 403 的来源看提示文案 | [RuleExecutionSemantics](docs/design/RuleExecutionSemantics.md) 第三节 | 第 3 节 |
| 书类目录自身分页（`BCA-RUNTIME-009`，已随 TestFlight 1.0 (50) 起的构建打包；引擎 fwq `BC-BOOK-061` 已部署） | 真机（TestFlight 1.0 (53) 及之后）：从 App **重交笔趣阁**（旧规则不带分页），打开一本长书（如《普罗之主》），目录应到最后一章、「从第 1 章开始读」开第一章 | [RuleExecutionSemantics](docs/design/RuleExecutionSemantics.md) 第三节 | 第 3 节 |
| 搜索全名直跳作品页的兜底（`BCA-RUNTIME-008`，已随 TestFlight 1.0 (50) 起的构建打包） | 真机（TestFlight 1.0 (53) 及之后）：piaotia 或 sto55 搜一部书的**完整书名**，应出现一条结果、点进去是这本书；搜书名的一部分照旧出列表 | [RuleExecutionSemantics](docs/design/RuleExecutionSemantics.md) 第三节 | 第 3 节 |
| POST 搜索与非 UTF-8 关键词（fwq `APP-MEMO-031`，Core 与 Runtime 已推送） | 真机：fwq 三站搜索复测通过后，从 App 重交 piaotia 搜「剑帝」 | fwq `BC-SEARCH-022` | fwq STATUS |
| 站点有声播放器后续：界面样式、倍速入口、`mediaAPI` 无语料 | 立项 | [Book-Kind-Wiring](docs/design/Book-Kind-Wiring-Design.md) 第十六节 | 第 1 节 optional 行 |
| 规则目录「推荐」改为「发现」：上方「站点示例」列表、Debug 下方「内部测试」沿用原横幅版式（2026-10-12 裁定；App 侧与服务端都已实施，示例站已发布，2026-10-22 又去掉了「发现」按本人生成 id 剔除公共条目的过滤） | 欠走查：Release 构建「发现」示例区（线上示例条数现查 `GET /catalog/sources?kinds=…`）、Debug 白名单账号（`CATALOG_INTERNAL_USER_IDS`）看到「内部测试」三类横幅、本人生成后转成示例的规则在 7 天内「发现」与「我的生成」两边都在；再要示例站经 fwq 以 `--catalog-section example` 发布（候选与条款核对表在需求文档第三节） | [Catalog-Page-Redesign](docs/design/Catalog-Page-Redesign-Design.md) 2.2 / 2.6；需求文档「fwq 需求：公共目录区分站点示例」（https://claude.ai/artifact/1qKBLaB16tzi8WRVByJZVr）；设计书（https://claude.ai/artifact/Mv6Qq1JTHRTtNHbd8aN72y）；画布（https://claude.ai/artifact/SrrBgFvcPSbwsnZdY4PxFg） | 第 2 节该行 |
| App Store 首发（AnyPortal，香港与台湾，免费）：ASC 填写项与提审状态现查 App Store Connect | **5 个内购没有随 1.0 (55) 送审**（控制台「App 内购买项目」里全是「草稿 · 准备提交」，版本页没有内购一栏；首批内购必须随版本送审，之后可在内购页单独送审）：用户 2026-10-22 改判重提——1.0 已从审核中移除（审核沙盒拿不到未附上的内购，购买页会显示「目前沒有可用的 StoreKit 商品」，按 2.1 被退的风险高）；用户要重新打一个包（不用 55），新包上传后在版本页选新构建、「App 内购买项目」一栏附上 5 个内购再提交审核；「在 App Store 上推广」不开（App 未处理 `PurchaseIntent`，要开先补代码） | Claude 文档「BrowseCraft 页面设计索引」的「App Store 内购项目图像」一节（勾选清单与即梦设定） | — |
| 隐私清单（`BrowseCraft/PrivacyInfo.xcprivacy`）：跟踪姿态接 ATT、顶层 `NSPrivacyTracking` false 且跟踪域名留空（用户 2026-10-20 裁定；清单、ATT 与 ASC 标签的来龙去脉见 status-log） | 欧洲经济区 / 英国 / 瑞士是否接 UMP 未定，不接则这三地只投受限广告；GoogleAppMeasurement / FirebaseAnalytics 当前版本不带自己的清单、其收集由 App 清单代为声明，升级 Firebase 后看新版是否自带、自带了就删掉 App 清单里重复的 | `BrowseCraft/PrivacyInfo.xcprivacy` 内注释；`RewardedAdPresenter.requestTrackingAuthorizationIfNeeded` 注释 | — |
| 埋点全覆盖（`BCA-OBS-001` ~ `005`） | 模拟器走查没走到的链路：视频 / 漫画链路、站点登录、来源增删启用、生成提交、购买结局与恢复、Apple 登录退出、删号、云同步、内容锁、推送、启动失败；PortalCore 的 SSV 延迟记录上线后回看 60 秒轮询窗口 | 有视频 / 漫画来源的模拟器或真机上用 `-FIRDebugEnabled` 启动、开 `log stream` 过滤 `Event logged` 补走；[Analytics-Events](docs/design/Analytics-Events-Design.md) | 第 9 节 |
| 给 fwq 的六条读书 kind 生成需求 | 需求一 / 三 / 四 / 五前半 fwq 已交付并真机通过（小說狂人最新章节 10-10 再修、待部署）；需求二记账、两端都不做；五后半目录分页 fwq 未定立场；六 fwq 不做 | Claude 文档「读书 kind 规则生成覆盖需求」（https://claude.ai/artifact/HnYM71goMZveUVJQQ4vhgk） | fwq STATUS |
| 2026-10-20 全量代码审计与发布前清单十二项（逐项状态见 STATUS 第 13 节） | ② 欠四处失败态的模拟器走查：Release 配置长按来源（#2）、站点书打开失败（#5）、预检挡下的网址提交（#6）、书详情重取失败横幅（#10），都要制造失败才看得到；③ #12 控制台侧七件由用户做（清单在 STATUS 第 13 节 #12 行）；⑤ 发布后路线图七批在报告里，待发布后立项；⑥ 服务器 `internal` 区漫画 `version` 分布待现查（只读脚本 fwq `site-research/server-queries/catalog_versions_ro.py`，ssh 到服务器 `docker compose exec -T api python -` 喂进去） | Claude 文档「BrowseCraft 全量代码审计报告 2026-10-20」（https://claude.ai/artifact/RqbnQE2ZiEEtsQ3aLKbfPq） | [第 13 节](docs/STATUS.md#13-全量代码审计2026-10-20) |

下一会话建议顺序：1.0 (55) 已提审（现查 App Store Connect；提审记录在 `docs/history/status-log.md` 末节）。先补上表审计行②的四处失败态走查与③的控制台侧七件 → 真机验收（STATUS 里 `not-run` 与 `simulator-passed` 的各行，看点都在上表；用户在真机上走，结果新增 `device-passed` 行、不改模拟器那几行）→ 续看同步两机对测 → 成功率一行有数据时的文案与活动推送点击（上表活动行）→ 活动脚本等发活动前再做。代码侧的复审项已全部收尾。

- **fwq 侧指针**（定义点与验证状态都在 fwq `docs/rules/STATUS.md`）：`BCA-RUNTIME-005`（fwq `APP-MEMO-026`）里「直接请求收到挑战页回退 WebView」一处仍欠真机，
  发版后由用户重交 toonily 验证，发版前 Cloudflare 站不要重生成；`BC-PREFLIGHT-066`（点推送停在原页、打开目录直接看到新规则）在 fwq 为 `not-run`，随规则目录页真机一起看；
  `BC-EVIDENCE-082` 与「选集无线路名标线路 N」在影视详情页清单里。真机结果记回 fwq STATUS 对应行（fwq 没有 `device-passed`，用 `fresh-passed` 并在流水写明是真机）。
- **设计新页面**：先读 Claude 文档「BrowseCraft 页面设计索引」（https://claude.ai/code/artifact/5c5f0bd7-543e-40af-bb70-b5c3f9d1edaf），
  开工时把新页面加进它的页面表，完成后更新那一行。颜色只在 `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift` 一处取值；
  底栏可见性只能挂在 `NavigationStack` 根页的规则见 [Coin-Ledger](docs/design/Coin-Ledger-Page-Redesign-Design.md) 第二节。
- **明确不做**：`决策 = rejected` 的 STATUS 行按名字跳过，不是待办。
  2026-10-11 新增一条：App 侧不显示每次生成的 `aiTokens` / `cloudCost`（服务端已随推送与 `/outcomes` 下发，App 忽略未知字段即可），
  理由与重开条件在 STATUS 第 2 节该行、目录页合同 2.3 末条。
- **遗留小项**：本机同步队列里 `local.default` 作用域下有几条早先留下的来源删除与收藏待传项，未处理。

## 2. 环境与命令速查

六个仓库是**同级 checkout 的 path 依赖**，没有版本 tag；App 的 `main` 只对得上兄弟仓的 `main`：

```
<parent>/                 # 任意父目录，七个仓库并排放；命令都以 ../<仓库> 相对 App 仓根目录写
  BrowseCraft/            # App
  BrowseCraftCore/  BrowseCraftDomain/  BrowseCraftRuntime/  BrowseCraftAPIKit/  BrowseCraftLog/
  fwq/                    # 规则生成引擎，BC-* 与 APP-MEMO-* 的定义点在这里
```

工具链：`xcodegen` 只保留 `/opt/homebrew` 下的 arm64 版；Homebrew 从源码编译要求独立的 Command Line Tools 与 Xcode 同版本。
命令行 build / test 前先看 `xcode-select -p`：机器上装着多个 Xcode 时，指向旧版（16.x）包解析会报 WebUI「incompatible tools version」，
不改系统设置的话给那条命令加 `DEVELOPER_DIR=<Xcode>.app/Contents/Developer`。
- **归档用 Xcode ≥ 27**（`BCA-BUILD-008`，[architecture.md](docs/architecture.md) 第 3 节）：本机版本现查 `xcodebuild -version`；要在 26.0.1 上跑测试，先在本地做等价改写、不提交（改法见 `docs/history/status-log.md` 2026-10-20 的记录）。
- **归档机必须有 `Config/CatalogEncryption.release.local.xcconfig`**（`BCA-BUILD-003`，判据在 [architecture.md](docs/architecture.md) 第 3 节）。
  prod key 本身已存进本机 macOS 登录钥匙串（2026-10-20；服务名「BrowseCraft catalog encryption key (BROWSECRAFT_CATALOG_ENCRYPTION_KEYS, Release)」、账户 `prod-v1`，
  钥匙串访问里搜 BrowseCraft catalog 即得），换机器时取出写回那份 local xcconfig；登录钥匙串不随 iCloud 同步，要跨机器得自己再存一份。

```bash
# 工程文件不同步时先重新生成（BCA-BUILD-001）；纯文档改动不需要。
scripts/regenerate-project.sh

# 三个代码闸门（pre-build）+ 本地化闸门（编译后，单独跑要传 Objects-normal 目录）+ 文档闸门
scripts/check-architecture-boundaries.sh     # BCA-ARCH-001 ~ 005
scripts/check-ad-configuration.sh            # BCA-BUILD-003
scripts/check-bundled-image-assets.sh        # BCA-BUILD-006 ~ 007
scripts/check-localization.py <Objects-normal 目录>
python3 scripts/check-docs.py                # BCA-DOC-010；fwq 不在同级 ../fwq 时加 --fwq <路径>；本机没有 AGENTS.md 时跳过它并报告

# build 与测试（AGENTS.md：只有用户明确要求时才跑）。destination 写「OS + 名字」，不写 UDID；
# 运行时用 iOS 26 及以上（iOS 18.5 跑不了测试）。
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' build
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' test -only-testing:BrowseCraftTests

# 包各自的测试
for d in BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit BrowseCraftLog; do
  (cd ../$d && swift test)
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
