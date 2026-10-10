# 数据库说明

- `BCA-DB-001` BrowseCraft 使用 GRDB `DatabaseMigrator` 管理本地 schema。`v1.initial-schema` 固化了首次正式迁移基线；
后续任何字段、约束或索引变化都必须注册新的、只追加不改名的迁移。已有同结构开发数据库会通过
`ifNotExists` 纳入 v1 迁移账本，但不承诺修复早期任意形态的开发数据库。

## 文件组织

- `AppDatabase.swift` 只负责数据库路径与执行迁移。
- 表、主键、唯一键和索引由 `Migrations/`（`AppDatabaseSchemaV1` 与 `AppDatabaseMigrations`）创建；Record 类型（`*Record+Schema.swift` 伴随文件或 Record 本体）只保留列名 `Columns`，不建表。
- `Records/User` 保存用户（含 coin 余额与版本号）、权益和用户级 UI 状态。
- `Records/Source` 保存站点来源配置。
- `Records/Favorite` 保存收藏快照。
- `Records/History` 保存漫画、视频、书籍历史快照。
- `Records/Book` 保存本地书籍、阅读进度和书签。
- `Records/Sync` 保存 iCloud 同步游标、本地待上传队列、CKRecord system fields，以及历史同步账本 `HistorySyncLedgerRecord`（`history_sync_ledger`，v8 迁移；三张历史表不入队列，每轮同步拿历史表与账本对比得出新增 / 改动 / 删除 / 恢复，见 [History-Resume-Sync-Design.md](../../../docs/design/History-Resume-Sync-Design.md)）。
- `Records/Temporary` 保存临时发现资源历史。
- `Repositories/`、`Sync/`、`Identity/` 分别放 GRDB 仓储实现、同步存储与身份存储。

## 当前规则

- `favorites` 是用户级聚合表：每个 `userID` 一行，内部用 JSON 保存漫画 / 视频 / 书籍收藏快照（`rssFavoritesJSON` 列随 RSS 下线留作死列），并保存一份派生 ID 列表用于快速判断收藏状态。
- `favorite_items` 是收藏同步明细表：每个 `userID + sourceID + itemID` 一行，取消收藏通过 `deletedAt` tombstone 表示。
- `favorites` 和阅读历史只关联 `users`，不直接外键关联 `sources`；删除来源时的连带删除由仓储在同一事务里显式执行（`BCA-DB-005`），不依赖外键级联。
- `sources` 使用 `userID + id` 复合主键，允许 `local.default` 和多个 cloud scope 保存相同 Source ID。
- `sync_queue` 使用 `accountScope + entityType + entityID` 唯一键，队列 ID 也包含 account scope；CloudKit 返回的 `retryAfter` 持久化为 `nextRetryAt`，协调器按账户恢复最早重试任务。
- Cloud 同步采用单一调度模型：`CloudSyncCoordinator` 统一处理账户恢复、本地变更、前台、远程通知、手动及定时重试；`CKSyncEngine.automaticallySync` 固定关闭，只执行协调器明确发起的 fetch/send。
- 每轮上传先冻结待处理队列快照，再按固定批大小排空；partial failure 保留到下一轮，不在同一轮立即重试。
- Zone 意外删除或账户加密数据重置时清理 engine state/system fields，并把仍有效的本地 Source、Favorite 重新入队，同时清空该账户的 `history_sync_ledger`，下一轮把本机现有历史当作新增重新登记上传；用户从 iCloud 存储管理执行 purge 时删除该 cloud scope 的本地缓存且不重新上传。
- `sync_state` 使用 `accountScope + scope + zoneName` 复合主键，账户之间不共享 CloudKit 游标。
- `cloud_record_metadata` 保存 CKRecord system fields/change tag，并按账户与 record name 隔离。
- Source、Favorite 和同步账本 Repository 在每次事务开始前捕获活动 account scope。
- 首次合并只复制 `local.default` 到目标 cloud scope，不删除或改写匿名空间。
- `BCA-DB-002` 禁止修改已发布迁移的实现或标识；schema 变化必须追加新迁移。
- `BCA-DB-003` 每次新增迁移都必须覆盖“上一正式版本数据库升级”与全新数据库创建，并执行 `foreign_key_check`。

## Source 删除规则

设计与各条删除路径的处理见 [删除来源时连带删除历史与收藏](../../../docs/design/Source-Deletion-Cascade-Design.md)。

- `sources.userID + sources.id` 拥有来源自身配置、同一用户空间的 Library 当前选择状态，以及该来源下的阅读历史与收藏。
- 删除 Source 使用软删除：写入 `sources.deletedAt`，并把删除动作写入 `sync_queue`（内置来源不入队）。
- `BCA-DB-004` 删除 Source 必须在当前选择匹配时清空 `user_library_state.selectedSourceID`、`listContextJSON`、`lastRefreshAt`；应用 iCloud 下载的来源删除时同样适用。
- `BCA-DB-005` 用户删除 Source 时，必须在同一写事务里删除该用户、该来源在 `comic_chapter_history`、`video_watch_history`、`book_reading_history` 的全部记录，并给该用户、该来源每条在册的 `favorite_items` 写删除标记、逐条把收藏删除写入 `sync_queue`，再重建 `favorites` 汇总；内置来源同样适用。应用 iCloud 下载的来源删除时，只删本机该来源的三张历史表记录，收藏由删除方设备的收藏删除标记经同步到达。
- 用户删除可在短暂窗口内撤销：撤销在一个写事务里把被删的来源、三张历史表记录与收藏原样写回，并把来源（非内置）与收藏以当前时间重新写入 `sync_queue` 为更新，覆盖尚未上传的删除。
- 不删除 `users`、`temporary_resource_history`、`book_reading_progress` 与 `book_bookmarks`。
- iCloud 区域被清除与「只用 iCloud 数据」两条账户级路径按各自规则硬删来源与收藏，不删阅读历史。
