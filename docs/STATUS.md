# 实施状态

本文是瞬时状态的唯一承载，形态与取值由 [文档索引](README.md) 第 5 节定义。
C 类设计文档不再承载 `implemented` / `pending` / `passed` 这类状态。

每格恰好一个值（`BCA-DOC-004`）。一个工作项同时存在多种验证事实时拆成多行（`BCA-DOC-005`）。
被覆盖的旧值追加到 [history/status-log.md](history/status-log.md)（`BCA-DOC-006`）。

条款列写 `未编号` 的行，是条款编号（D3）尚未执行的结果，不是「没有约束」。

## 0. 读这张表的纪律

**本表的行不会随条款落地自动退休。** 开工前的三步核对（都是零成本）：在 `BrowseCraft/` 与四个包里
grep 该行点名的类型或文件，看有没有实现；在本表里交叉查同一工作项有没有别的行标了 `implemented`；
该项若有产物可查（真机日志、模拟器截图、测试产物），按产物时间线看症状还在不在。

并且要看全五个状态列——`设计` 列为 `superseded` 就说明该设计已被取代，此时 `实施=not-started`
是正确的记法而不是过期。

`验证` 列的三级不可互相推断：`full-suite-passed` 是离线测试全过，`simulator-passed` 是模拟器上
人工走通了流程，`device-passed` 是用户在真机上确认。模拟器通过**不等于**真机通过。

## 1. 读书 kind（book）

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 读书 kind App 侧接线立项（三批范围、五仓改动清单、目录接口封闭枚举的兼容硬约束与发布策略） | `BC-BOOK-001` `BC-BOOK-012` | required | approved | implemented | full-suite-passed | 7ae4270 | 2026-09-13 |
| 批次 A：APIKit / Core / Domain 的 book 枚举与 `BookSiteRuleValidator`、各分流点补 book | `BC-BOOK-001` | required | approved | implemented | full-suite-passed | 43dfef2 | 2026-09-14 |
| 批次 B：Runtime 按规则取正文与音频、RWPM 装配、Readium 出版物构建 | `BC-BOOK-012` | required | approved | implemented | full-suite-passed | ac37e7f | 2026-09-14 |
| 批次 C：添加来源入口、站点书详情、共用 EPUB 阅读器、`SiteBookIdentity` 与迁移 v4 | `BC-BOOK-012` | required | approved | implemented | full-suite-passed | 8b280ff | 2026-09-14 |
| 站点书整链（sfacg 添加 → 列表 → 作品 → 章节 → 正文 → 续读） | `BC-BOOK-012` | required | approved | implemented | device-passed | 9b3a7d8 | 2026-09-15 |
| 站点有声作品的播放器（AudioNavigator 内核、远程 mp3 经 HTTPContainer、锁屏控制） | `BC-BOOK-012` | required | approved | implemented | simulator-passed | 11821b6 | 2026-09-14 |
| 站点书搜索：由规则声明，与漫画 / 影视同一条合同 | `BC-SEARCH-004` | required | approved | implemented | full-suite-passed | 84af71b | 2026-09-15 |
| 站点书进 History 页：与漫画、视频同列 | 未编号 | required | approved | implemented | full-suite-passed | 79512a9 | 2026-09-16 |
| book catalog 不发布进公共目录——2026-09-14 用户裁决发布 biquhua 后被取代，当前靠服务器 `kinds` 缺省不回 book | `BC-BOOK-001` | rejected | superseded | reverted | not-run | 43dfef2 | 2026-09-14 |
| 四个接口变体（list / detail / reader 的 API 形态）——无语料，另立项 | `BC-BOOK-012` | optional | draft | not-started | not-run | 8b280ff | 2026-09-14 |
| 本地书籍导入 B0：Domain 模型、三个仓储协议、六用例、迁移 v3 与边界脚本禁 Readium | 未编号 | required | approved | implemented | full-suite-passed | 4811cb1 | 2026-09-13 |
| 本地书籍导入 B1：Readium 环境 / 嗅探器 / 打开器、容器内文件存储、三个 GRDB Record 与仓储 | 未编号 | required | approved | implemented | full-suite-passed | 8a5b8a9 | 2026-09-13 |
| 本地书籍导入 B2：书架与 EPUB 阅读器、目录跳转、书签、退出重开续读 | 未编号 | required | approved | implemented | simulator-passed | 1c78bb2 | 2026-09-14 |
| 本地书籍导入 B3：有声书播放器——按「入口不对用户暴露」的裁决不做 | 未编号 | rejected | superseded | not-started | not-run | 1c78bb2 | 2026-09-14 |
| 本地导入入口已藏：去掉 Library 工具栏「书籍」与 RootView 书架装配，代码留给站点抓取路复用 | 未编号 | required | approved | implemented | full-suite-passed | 1c78bb2 | 2026-09-14 |
| Readium Swift Toolkit 3.11.0 选型与 SwiftSoup fork 覆盖 | 未编号 | required | approved | implemented | full-suite-passed | 7ad2704 | 2026-09-13 |
| PDF 与 CBZ 不接（PDF 见 `BC-BOOK-012`，CBZ 漫画线保持自研阅读器） | `BC-BOOK-012` | rejected | approved | not-started | not-run | f443602 | 2026-09-13 |

## 2. 规则目录

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 已添加来源的「更新规则」入口——被「已添加来源跟随目录自动更新」取代 | 未编号 | rejected | superseded | reverted | not-run | 175847d | 2026-09-30 |
| 已添加来源跟随目录自动更新（目录页读取、启动与回到前台时静默覆盖本地副本） | 未编号 | required | approved | implemented | targeted-passed | 3646c2e | 2026-09-30 |
| 同站多条来源的副标题显示各自入口地址 | 未编号 | required | approved | implemented | device-passed | 1513a0f | 2026-09-15 |
| 规则目录页重设计：推荐 / 我的生成分栏，推荐按类型分区，我的生成按时间线（方案 A） | 未编号 | required | approved | implemented | full-suite-passed | 9c03d27 | 2026-09-30 |
| 来源页重设计：正在使用置顶、点来源即打开库、已暂停区与启用窗口、长按菜单（方案 A） | 未编号 | required | approved | implemented | full-suite-passed | 2c0908a | 2026-10-01 |
| 来源页重设计的模拟器走查：切换成功跳库 / 失败留在原页、「更多位置」打开购买页、iCloud 恢复失败下拉重试（来源页与收藏页） | 未编号 | required | approved | implemented | simulator-passed | 448615c | 2026-10-01 |
| 收藏页重设计：封面卡片行、类型筛选（全部与三类一直显示）、按天分组、左滑取消收藏与撤销、来源状态 | 未编号 | required | approved | implemented | full-suite-passed | a5dc313 | 2026-10-03 |
| 收藏页重设计的模拟器走查：筛选与某类为 0、按天分组、左滑与长按取消收藏及撤销、在库中查看来源、三种来源状态、空状态与恢复失败下拉重试、深色、库页爱心同步 | 未编号 | required | approved | implemented | simulator-passed | a5dc313 | 2026-10-03 |
| 历史页重设计：继续卡片、看到哪里与视频进度、类型筛选、按天分组、按作品删除与撤销、来源状态；封面与撤销提示条与收藏页共用 | 未编号 | required | approved | implemented | full-suite-passed | 9ebb107 | 2026-10-03 |
| 设置页重设计：自绘大标题、账号卡（余额与看广告 +N、未登录系统登录按钮与不计奖励的看广告）、高级版入口卡、同步与存储 / 隐私与诊断 / 关于三组卡片行、退出登录确认框；下线书签页、复制诊断码行与两张图标 | 未编号 | required | approved | implemented | full-suite-passed | 3129a73 | 2026-10-03 |
| 设置页重设计的模拟器走查：未登录浅色与深色、系统登录按钮、未登录看广告（加载中、播完提示不计 coin）、已登录浅色与深色（临时注入）、诊断码与账号 ID 复制、退出确认框、进入 coin 记录子页 | 未编号 | required | approved | implemented | simulator-passed | 3129a73 | 2026-10-03 |
| coin 记录页重设计：隐藏底栏只留返回、余额卡与服务端价格说明、按天分组的卡片行、获得蓝底与消耗灰底图标、获得色 `gain`、骨架、失败与空状态可下拉、翻页与到底提示 | 未编号 | required | approved | implemented | full-suite-passed | ea2fefc | 2026-10-03 |
| coin 记录页重设计的模拟器走查（真实登录账号）：底栏隐藏只留返回、返回后底栏恢复、余额卡与价格说明、按天分组与跨天翻页到底、六种原因图标与获得色、深色、内购页仍隐藏底栏 | 未编号 | required | approved | implemented | simulator-passed | ea2fefc | 2026-10-03 |
| 缓存页重设计：隐藏底栏、用量卡（两块图片缓存分开计、写合计最多）、封面与漫画页上限、清除不弹确认并补清列表缩略图与网页 / 系统网络缓存（不碰 Cookie 与本地存储）、清除结果 | 未编号 | required | approved | implemented | full-suite-passed | e879196 | 2026-10-03 |
| 缓存页重设计的模拟器走查（真实登录账号）：底栏隐藏只留返回、用量与磁盘实测一致、清除后两块图片缓存归零并显示释放结果、Cookie / 网页本地存储 / 数据库未动而网络缓存已清、改上限后合计最多随之变化、深色、返回后底栏恢复 | 未编号 | required | approved | implemented | simulator-passed | e879196 | 2026-10-03 |
| 云同步页重设计：隐藏底栏只留返回、状态卡（按优先级只取一种状态）、开关、同步的内容（来源与收藏带条数、历史与阅读进度只在本机）、上次同步一行、下拉代替刷新 / 关联 / 同步 / 重试四个按钮、首次开启窗口改卡片样式；删去不再使用的词条 | 未编号 | required | approved | implemented | full-suite-passed | 7f42ed9 | 2026-10-04 |
| 云同步页重设计的模拟器走查（真实登录账号）：底栏隐藏只留返回、返回后底栏恢复、未开启、条数与数据库一致、正在检查 iCloud、首次开启窗口并选「合并本机数据」、正在同步、已同步与上次同步一行、下拉同步、同步出错卡、关闭再打开开关、深色；未登录 iCloud 与提交中状态未走到 | 未编号 | required | approved | implemented | simulator-passed | 7f42ed9 | 2026-10-04 |
| 历史页重设计的模拟器走查：继续卡片三种类型色、看到哪里与进度条、筛选与某类为 0、只有一条、按天分组、左滑与长按删除及撤销（漫画整部删除与整部写回）、在库中查看来源、已暂停 / 已删除 / 未知 / 临时资源、空状态与去库里逛逛、深色、收藏页回归 | 未编号 | required | approved | implemented | simulator-passed | 9ebb107 | 2026-10-03 |

## 3. 影视线运行期

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 运行期广告过滤承接规则匹配结果（App 侧对规则匹配到的候选执行过滤） | `APP-MEMO-008` | required | approved | implemented | full-suite-passed | ff58d6a | 2026-08-29 |
| jable.tv M3U8 播放规则的抽取根因（结论已由 fwq `BC-PLAYBACK-049` 承接） | `BC-PLAYBACK-049` | required | superseded | not-started | not-run | 4a3814b | 2026-08-21 |

## 4. 身份与同步

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 身份边界切换到 Sign in with Apple 与后端生成的 AppUser UUID | 未编号 | required | approved | implemented | full-suite-passed | eeb288e | 2026-07-28 |
| CloudKit 上传前的安全门禁——记录大小预算（900 KB / 800 KB / 8 KB）、URL userinfo、本地 account scope 泄漏：`CloudSyncPayloadSecurityValidator` 已实施并接线 | `BCA-SYNC-008` | required | approved | implemented | full-suite-passed | bed4ab3 | 2026-07-25 |
| CloudKit 门禁的 Header 名称拦截与 `context.*` / Request Body / `keyHex` / `ivHex` / constant value 字面量扫描——实现有意收窄为「不推测站点规则常量是否敏感」，13 例固定输入钉住该取值 | `BCA-SYNC-008` | optional | superseded | not-started | full-suite-passed | bed4ab3 | 2026-07-25 |
| Phase0 审计的安全结论已提升为 C：排除数据、冲突与删除、凭据引用三条成 `BCA-SYNC-009` ~ `011`，未实施的全面扫描部分显式声明为有意收窄 | `BCA-SYNC-009` `BCA-SYNC-010` `BCA-SYNC-011` | required | approved | implemented | static-audit-passed | 69779bb | 2026-09-19 |
| RSS 整体下线：删功能、迁移 v6 清存量、同步跳过 rss、书籍收藏改记 book | 未编号 | required | approved | implemented | full-suite-passed | f263274 | 2026-09-16 |
| 删除来源连带删除历史与收藏：用户删除时删三张历史表、给收藏写删除标记并入队；iCloud 应用远端删除时删本机历史并清空当前选择；删除后底部可撤销并原样写回；删除与撤销后刷新历史、收藏与库页；底部文案改写 | `BCA-DB-004` `BCA-DB-005` | required | approved | implemented | full-suite-passed | c2b2437 | 2026-10-03 |
| 删除来源连带删除的模拟器走查：左滑删除非内置来源与长按删除内置来源，历史、收藏、库页爱心随删除消失、随撤销回来，撤销后改回当前来源 | `BCA-DB-004` `BCA-DB-005` | required | approved | implemented | simulator-passed | c2b2437 | 2026-10-03 |
| 续看位置同步到 iCloud（每部作品一条精简记录：看到哪一章 / 哪一集、页码或秒数；不传整张历史表）——已立项，待设计；动工前须先裁决改写 `BCA-SYNC-009` 里「阅读进度与历史记录」一项 | `BCA-SYNC-009` | optional | draft | not-started | not-run | 7f42ed9 | 2026-10-04 |

## 5. 文档架构迁移

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D0 冻结基线：现状量化、逐份 C/S/H/E 判定、五处 RSS 漂移 | `BCA-DOC-001` | required | approved | implemented | static-audit-passed | 2ce6b99 | 2026-09-19 |
| D1 建索引 + 只移动文件：12 份迁入 `docs/`，新建索引，修五处 RSS 漂移 | `BCA-DOC-002` `BCA-DOC-003` | required | approved | implemented | static-audit-passed | 2ce6b99 | 2026-09-19 |
| D2 状态出设计文档：四份 C 类的状态头与两处验证节按三分法分流 | `BCA-DOC-007` `BCA-DOC-008` | required | approved | implemented | static-audit-passed | 812fde5 | 2026-09-19 |
| D3 条款编号与混装拆分：分配 `BCA-*` ID，fwq 已定义的改引用点，拆混装文档 | `BCA-DOC-001` `BCA-DOC-002` | required | approved | implemented | static-audit-passed | 812fde5 | 2026-09-19 |
| fwq 的 `protectedResource` 与 `executionPolicy` 两句只有正文没有稳定 ID——2026-10-03 裁定不请 fwq 分配：它们是生成器的发布偏好与默认值，不是 App 的执行约束，App 侧文档本就未引用 | `BCA-DOC-001` | rejected | superseded | not-started | not-run | a4433eb | 2026-10-03 |
| C 类里的散文硬条款一次扫完编号：逐行分类后确认真条款 22 条，其余是描述句、章节标题与已编号条款的续行 | `BCA-DOC-002` | required | approved | implemented | static-audit-passed | c0a72fe | 2026-09-19 |
| D4 机器闸门 `scripts/check-docs.py`：A1–A10 十项，每项经反向植入验证会红 | `BCA-DOC-010` | required | approved | implemented | targeted-passed | a330927 | 2026-09-19 |
| D5 `HANDOFF.md` 会话入口：四样内容，只记现查口径不记数字，只记纯 App 侧的工作 | `BCA-DOC-011` | required | approved | implemented | targeted-passed | a2adece | 2026-09-19 |
| fwq 可写文件里指向 App 文档的九处旧路径已更正；`docs/history/` 十一处按只读归档未动，查迁移对照表 | 未编号 | required | approved | implemented | static-audit-passed | 4fd6087 | 2026-09-19 |
| `BrowseCraftCore` 文档迁移：十份进 `docs/design` 与 `docs/history`，建索引，三份混装按节三分 | `BCA-DOC-009` | required | approved | implemented | static-audit-passed | 69233d1 | 2026-09-19 |
| Core 预检合同按 v3 收敛：一跳与 family coverage 归档，组件名对齐代码，白名单两条撤回 | `BC-PREFLIGHT-030` | required | approved | implemented | static-audit-passed | 6f6dc80 | 2026-09-19 |
| A10 文档点名的代码符号必须存在（fwq `BC-DOC-028` 那类）：白名单只许收敛，识别家族通配与路径段 | `BCA-DOC-014` | required | approved | implemented | targeted-passed | 15394c2 | 2026-09-19 |
| `scripts/update-rules-package.sh` 已确认是死脚本并删除：`BrowseCraftRulesKit` 仓库不存在、`project.yml` 零引用、`Package.resolved` 零命中 | 未编号 | required | approved | implemented | static-audit-passed | 2b4bd07 | 2026-09-19 |
| `BookBookmarksSheet` 是设计里不存在的类型名——书签功能已实现，呈现层内联在 `BookReaderView`；文档已按实际改写，白名单撤回 | `BCA-DOC-014` | required | approved | implemented | static-audit-passed | 2b4bd07 | 2026-09-19 |
| 规则编辑入口下线：`SourceDebugView` 的「Edit JSON」摘除、两个零引用编辑视图删除，规则一律只读 | `BCA-UI-003` | required | approved | implemented | static-audit-passed | 1b990b5 | 2026-09-19 |
| 规则编辑下线遗留的死代码链已清：五个文件 207 行，含 Service 的两个注入依赖与组合根、测试替身的装配 | 未编号 | required | approved | implemented | full-suite-passed | 4527def | 2026-09-19 |
| 规则编辑下线遗留死代码第二批：更新 / 复制 / 导入 / 导出四类用例、Coordinator 与两个测试文件整链删除 958 行，只读格式化独立为 `SourceRuleDebugJSONFormatter` | `BCA-UI-003` | required | approved | implemented | full-suite-passed | af2e331 | 2026-09-19 |
| `scripts/regenerate-project.sh` 已恢复：CLT 升到 27.0、arm64 xcodegen 2.46.0 从源码装好，`/usr/local/bin` 的 x86_64 旧链接已移除，bash 与 zsh 下都命中 arm64 版 | `BCA-BUILD-001` | required | approved | implemented | targeted-passed | af931e1 | 2026-09-19 |
| 模拟器 `build-for-testing` 链接失败已修：`BrowseCraftRuntime` 的 `Package.swift` 缺对 `BrowseCraftRuleModels` 的 product 声明，动态链接时符号解析不到；generic destination 静态链接下不暴露 | `BCA-ARCH-002` | required | approved | implemented | full-suite-passed | 4527def | 2026-09-19 |
| iOS 18.5 模拟器运行时跑不了测试（缺 `libswiftWebKit.dylib`）——裁决不修，测试口径统一到 iOS 26 及以上；`HANDOFF.md` 与设计文档的命令已改 iPhone 17 Pro | 未编号 | rejected | approved | not-started | targeted-passed | af931e1 | 2026-09-19 |
| 9 条 `BCA-*` 定义点曾只在被 `.gitignore` 的 `AGENTS.md` 里——已迁入跟踪的 C 类文档，`AGENTS.md` 收成纪律与指针（与 fwq 同构），闸门加 A11 守住 | `BCA-DOC-015` | required | approved | implemented | static-audit-passed | 30f9713 | 2026-09-19 |

## 6. 代码审计（2026-09-18）

原始清单与逐项论证在 [history/2026-09-18-code-audit.md](history/2026-09-18-code-audit.md) 第 5 节。
本节只承载状态：**要判断「今天还剩什么」看本节即可，不必读原文**。
「前提被测量推翻」的条目记为 `决策=rejected` + `验证=targeted-passed`——测量做过且是结论的依据，
条目本身不实施。

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 阶段 0 闸门基线（F0-1~4）：四包严格并发、边界脚本 import 写法与三个引用方向、`print`/`try!` 扩到四包 | `BCA-ARCH-004` | required | approved | implemented | static-audit-passed | 1febbf1 | 2026-09-18 |
| 阶段 1 清零 37 条编译器警告（F1-1~11）：App 与测试目标均 0 条 | `BCA-ARCH-007` | required | approved | implemented | static-audit-passed | 3af597e | 2026-09-18 |
| F2-1 正则缓存、F2-2 按目标宽度降采样解码成为共享 pipeline 的通用机制 | 未编号 | required | approved | implemented | static-audit-passed | 305895f | 2026-09-18 |
| F2-3 前半与 F2-4：封面请求按标识变化只构造一次，按测得单元格尺寸声明 thumbnail 解码 | 未编号 | required | approved | implemented | static-audit-passed | 718ea07 | 2026-09-18 |
| F2-3 后半：显式 `ImagePrefetcher` 预取——不做：`LazyVGrid` 本就提前实例化下一屏单元格、`LazyImage` 随之开始加载，显式预取的增量收益没有测到 | 未编号 | rejected | superseded | not-started | not-run | 718ea07 | 2026-09-19 |
| F2-5 进列表先读后写与来源配置解码缓存、F2-6 读书线读库经 actor 离开主线程 | 未编号 | required | approved | implemented | not-run | 0baf3e3 | 2026-09-18 |
| F2-7 WebView 稳定判定改 MutationObserver 静默窗口——前提被固定输入测量推翻，条目关闭 | 未编号 | rejected | superseded | not-started | targeted-passed | 3286951 | 2026-09-18 |
| F2-8 发现分析器传 `Document` 不传 `html`、F2-12/F2-13 历史批量删除合并写事务 | 未编号 | required | approved | implemented | static-audit-passed | 5d5e421 | 2026-09-18 |
| F2-9 `MobileAds.start()` 延后到引导完成——**已实施后回退**：必须早于 `FirebaseApp.configure`，否则覆盖 Crashlytics 信号处理器 | 未编号 | required | superseded | reverted | targeted-passed | 810c9ce | 2026-09-18 |
| F2-10 预检复用 WKWebView 与数据存储——判定不动：每次取样各自一个非持久存储是隔离前提 | 未编号 | rejected | approved | not-started | not-run | 5d5e421 | 2026-09-18 |
| F2-11 资产瘦身：占位图砍冗余 scale 槽位 + 按渲染宽度选有损，内购背景转 HEVC | `BCA-BUILD-006` | required | approved | implemented | targeted-passed | 7ac3d47 | 2026-09-18 |
| 阶段 3 F3-3 Core 拆「规则模型 / 解析」两 target、F3-4 退役候选合同别名 | `BCA-ARCH-002` | required | approved | implemented | static-audit-passed | 473e8c7 | 2026-09-18 |
| 阶段 3 F3-1 包侧加 `Tests/`——前提被测量否定：104 个 App 测试文件里 101 个 `@testable import` App | 未编号 | rejected | superseded | not-started | targeted-passed | 473e8c7 | 2026-09-18 |
| 阶段 3 F3-2 `DefaultRuleExtractionEngine` 的默认构造改注入——判定不再需要：与解析器同在一个 target | 未编号 | rejected | superseded | not-started | not-run | 473e8c7 | 2026-09-18 |
| 引导失败诊断：错误类型自己声明可安全记录的摘要，Keychain 的 `OSStatus` 可见 | `BCA-SYNC-001` | required | approved | implemented | static-audit-passed | 367da97 | 2026-09-18 |
| 边界豁免收敛：`Features→Infrastructure` 七条与 `Shared` 两个方向清掉，豁免清单降到 1 条 | `BCA-BUILD-005` | required | approved | implemented | static-audit-passed | b1c60e7 | 2026-09-18 |
| WebView 就绪选择器：加载器按「规则要提取的内容到了没」提前返回，等待 3438 ms → 314 ms | `APP-MEMO-016` | required | approved | implemented | device-passed | 54e2df3 | 2026-09-18 |
| Swift 6 语言模式：App 与四个包切换，并加闸门把「警告为零」固化成编译错误 | `BCA-ARCH-007` | required | approved | implemented | static-audit-passed | 2f769ae | 2026-09-18 |
| 封面请求重复构造——代价测量否掉：重复的只是请求构造，改发布时序要动两个 ViewModel，条目关闭 | 未编号 | rejected | superseded | not-started | targeted-passed | 70b2700 | 2026-09-18 |

## 7. 规则生成入口

| 工作项 | 条款 | 决策 | 设计 | 实施 | 验证 | 检查点 | 更新日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 合格入口页引导屏：两个要素做成添加来源的首次必过一屏，输入页留常驻回看入口，四种入口页拒因的失败行挂教程入口 | `BC-PAGE-060` | required | approved | implemented | static-audit-passed | 90bd347 | 2026-09-20 |
| 引导屏做成输入页上的常驻折叠段（不拦路）——用户 2026-09-20 裁定用首次必过一屏，折叠态大概率没人展开 | `BC-PAGE-060` | rejected | superseded | not-started | not-run | 90bd347 | 2026-09-20 |
| 输入框「这看起来是网站首页」的本地软提示——用户 2026-09-20 裁定不做：服务器真实提交 34 条里根入口只有 5 条，且单 list 带分页的首页本就合格，提示会对那类页面说错话 | 未编号 | rejected | approved | not-started | targeted-passed | 90bd347 | 2026-09-20 |
