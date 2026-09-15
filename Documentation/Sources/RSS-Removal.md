# RSS 整体下线（App 侧）

更新时间：2026-09-16
状态：**已实施，未真机**
影响范围：BrowseCraftCore、BrowseCraftDomain、BrowseCraftRuntime、BrowseCraftAPIKit、BrowseCraft 五个仓库；PortalCore 目录接口缺省值另见其迁移计划 §14.12

## 一、裁决

- 2026-09-13：规则生成侧下线 RSS（fwq），**App 的 RSS 功能当时保留**。
- 2026-09-16：用户「book 的浏览记录……同时可以把 rss 删除」，并在两项提问里裁决 **「App 全删，服务器也下线」**、**「先做 book 历史，再删 RSS」**。

## 二、删掉了什么

| 仓库 | 内容 |
|---|---|
| Core | `Parsing/Feed`（RSS/Atom feed 与详情解析器、模型、端口）及其测试；`SourceRuntimeKind.rss`、`SourceDefinition.rss`、`RSSSourceDefinition`、`SourceRefreshPolicy`；`Documentation/Phase5RSSParsingMigration.md` |
| Domain | `SourceConfiguration.rss` 与 `RSSSourceConfiguration`、`SourceType.rss`、`CatalogSourceKind.rss`、`SourceRequestPurpose.rss`、两个 RSS 请求头、`RSSContentPayload` 别名与只给 RSS 用的旧缓存编解码 |
| Runtime | `RSS/`（RSS 运行时、工厂、feed 加载、媒体分类）；`SourceRuntimeFactory` 的 RSS 槽位 |
| APIKit | `BrowseCraftCatalogSourceKind.rss`：目录请求改为 `kinds=comic,video,book`，服务端即使返回 rss 也按未知 kind 逐条跳过 |
| App | 添加来源的 RSS 入口与 RSS 发现（含 RSSHub 候选）、RSS 列表 / 详情 / 播放器、RSS 阅读历史（表、记录、仓储、历史页分支）、RSS 收藏分支、目录物化与来源校验的 RSS 分支、推荐导入选项的 RSS 识别、诊断枚举的 RSS 取值；以及从未被赋值过的 `RuntimeSourceImportView` 导入外壳（它只服务 comic / rss 两种，`AddSourceView.runtimeSourceKind` 无人写入） |

**保留**：规则合同里的 `ResourcePipelineContentType.rssAttachment`（规则枚举值，fwq 的 Core 合同闸门直接读它，删了会让含它的规则解码失败）；Runtime 探测词表里的 `feedStructure` 词；发现用例里排除 `/rss` 链接的清单；`favorites.rssFavoritesJSON` 列（从未写入，去掉要重建表）。

## 三、存量数据：迁移 `v6.remove-rss`

App 读来源列表时任何一行解码失败都会让整张列表抛错（`GRDBSourceRepository.fetchSources`），所以 RSS 数据**必须在迁移里清掉**，不能留给运行时：

1. 删 RSS 来源在 `sync_queue` 里的待上传项，再删 `sources` 里 `kind = 'rss'` 的行。
2. **书籍收藏改记 book**：书籍条目的内容形态是 `article`，此前 `ToggleFavoriteUseCase` 把 `article` 一律记成 rss 收藏（从收藏页点开进的是 RSS 详情，本就是坏的）。属于书籍来源的 rss 收藏改为 `book`（列与 `itemJSON` 里的 kind 同改）；其余 rss 收藏连同同步队列项删除。
3. 删 `rss_reading_history` 表（两个索引随表删除）。
4. 按用户重建 `favorites` 聚合。

不给云端排删除：旧版设备上的 RSS 数据不动。

## 四、同步与新增的 book 收藏

- `SourceCloudPayload.isRemovedRSS`：下行时 rss 来源逐条跳过（与 `isUnsupportedVideoV1` 同一处守门）。
- `FavoriteItemSyncService`：kind 认不得的收藏逐条跳过——否则 `FavoriteItemRecord(payload:)` 抛错会拖垮整批合并；已下线的 rss 与更新版本才有的类型都走这里。
- `FavoriteContentKind.book`：收藏页点开进 `BookSiteDetailView`（与 Library 点开站点书同一个详情页）。`ToggleFavoriteUseCase` 的 `article → book`、`gallery → comic`。
- 历史页空状态文案由「打开过的条目和读过的章节」改为「读过的漫画、书和看过的视频」。

## 五、固定输入与验证

- `RemoveRSSMigrationTests.rssDataIsRemovedAndBookFavoritesSurviveAsBook`：迁到 v5 写入 RSS 来源、书籍的 rss 收藏、其它 rss 收藏与三条同步队列项，再迁到最新——只剩书籍来源、`rss_reading_history` 不存在、收藏只剩改记 book 的那条且 `itemJSON` 解码出 `.book`、队列只剩书籍收藏那条、聚合重建。
- `AppDatabaseSchemaSnapshotTests` 快照去掉一表两索引。
- 原先拿 RSS 来源当样例的同步 / CloudKit / 数据库 / 账户用例改用 `TestSourceFixtures.pluginConfiguration()`；专测 RSS 的用例（添加 RSS 源两条、RSS 列表不翻页、四条 RSS 推荐、两个 RSS 解析器测试文件、RSS 运行时 / feed 加载 / RSSHub 发现测试）随功能删除。
- **验证**：Core 224 项（4 跳过）、APIKit 33 项、Runtime 包编译过；App（iPhone 16 Pro 模拟器 iOS 18.5）全量 493 项 / 86 组 + XCTest 39 项全过，架构边界干净。**未真机**：升级后原书籍收藏仍在且点开进书籍详情、添加来源页不再有 RSS、Library / 历史 / 收藏无异常，由用户真机验。
