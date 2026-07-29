# 数据库说明

BrowseCraft 使用 GRDB `DatabaseMigrator` 管理本地 schema。`v1.initial-schema` 固化了首次正式迁移基线；
后续任何字段、约束或索引变化都必须注册新的、只追加不改名的迁移。已有同结构开发数据库会通过
`ifNotExists` 纳入 v1 迁移账本，但不承诺修复早期任意形态的开发数据库。

## 文件组织

- `AppDatabase.swift` 只负责数据库路径、表创建顺序和索引创建顺序。
- 每张表的字段、主键、唯一键和索引放在对应的 `*Record+Schema.swift`。
- `Records/User` 保存用户、权益和用户级 UI 状态。
- `Records/Source` 保存站点来源配置。
- `Records/Favorite` 保存收藏快照。
- `Records/History` 保存 RSS、漫画、视频历史快照。
- `Records/Sync` 保存 iCloud 同步游标和本地待上传队列。
- `Records/Temporary` 保存临时发现资源历史。

## 当前规则

- `favorites` 是用户级聚合表：每个 `userID` 一行，内部用 JSON 保存 RSS / 漫画 / 视频收藏快照，并保存一份派生 ID 列表用于快速判断收藏状态。
- `favorite_items` 是收藏同步明细表：每个 `userID + sourceID + itemID` 一行，取消收藏通过 `deletedAt` tombstone 表示。
- `favorites` 和阅读历史只关联 `users`，不直接外键关联 `sources`，避免删除来源时误删独立用户快照。
- `sources` 使用 `userID + id` 复合主键，允许 `local.default` 和多个 cloud scope 保存相同 Source ID。
- `sync_queue` 使用 `accountScope + entityType + entityID` 唯一键，队列 ID 也包含 account scope；CloudKit 返回的 `retryAfter` 持久化为 `nextRetryAt`，协调器按账户恢复最早重试任务。
- Cloud 同步采用单一调度模型：`CloudSyncCoordinator` 统一处理账户恢复、本地变更、前台、远程通知、手动及定时重试；`CKSyncEngine.automaticallySync` 固定关闭，只执行协调器明确发起的 fetch/send。
- 每轮上传先冻结待处理队列快照，再按固定批大小排空；partial failure 保留到下一轮，不在同一轮立即重试。
- Zone 意外删除或账户加密数据重置时清理 engine state/system fields，并把仍有效的本地 Source、Favorite 重新入队；用户从 iCloud 存储管理执行 purge 时删除该 cloud scope 的本地缓存且不重新上传。
- `sync_state` 使用 `accountScope + scope + zoneName` 复合主键，账户之间不共享 CloudKit 游标。
- `cloud_record_metadata` 保存 CKRecord system fields/change tag，并按账户与 record name 隔离。
- Source、Favorite 和同步账本 Repository 在每次事务开始前捕获活动 account scope。
- 首次合并只复制 `local.default` 到目标 cloud scope，不删除或改写匿名空间。
- 禁止修改已发布迁移的实现或标识；schema 变化必须追加新迁移。
- 每次新增迁移都必须覆盖“上一正式版本数据库升级”与全新数据库创建，并执行 `foreign_key_check`。

## Source 删除规则

- `sources.userID + sources.id` 只拥有来源自身配置，以及同一用户空间的 Library 当前选择状态。
- 删除 Source 使用软删除：写入 `sources.deletedAt`，并把删除动作写入 `sync_queue`。
- 删除 Source 不删除 `rss_reading_history`、`comic_chapter_history`、`video_watch_history`。
- 删除 Source 必须在当前选择匹配时清空 `user_library_state.selectedSourceID`、`listContextJSON`、`lastRefreshAt`。
- 不删除 `users`。
- 不删除 `favorites` 或阅读历史；这些用户快照独立于来源生命周期。
