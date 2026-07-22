# 数据库说明

BrowseCraft 当前仍处于开发阶段。数据库层优先保持“当前最终 schema”清晰可读，暂不兼容旧开发数据库。
阶段 3 修改 schema 后，需要删除开发设备上的 App，再由 `AppDatabase` 创建完整的新数据库。
未来正式发布时采用的 account-scoped 迁移方案记录在
`Documentation/CloudKit/AccountScopedDatabaseMigration-Memo.md`。

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
- `favorite_items` 是收藏同步明细表：每个 `userID + itemID` 一行，取消收藏通过 `deletedAt` tombstone 表示。
- `favorites` 和阅读历史只关联 `users`，不直接外键关联 `sources`，避免删除来源时误删独立用户快照。
- `sources` 使用 `userID + id` 复合主键，允许 `local.default` 和多个 cloud scope 保存相同 Source ID。
- `sync_queue` 使用 `accountScope + entityType + entityID` 唯一键，队列 ID 也包含 account scope。
- `sync_state` 使用 `accountScope + scope + zoneName` 复合主键，账户之间不共享 CloudKit 游标。
- Source、Favorite 和同步账本 Repository 在每次事务开始前捕获活动 account scope。
- 首次合并只复制 `local.default` 到目标 cloud scope，不删除或改写匿名空间。
- 当前开发阶段不执行旧库迁移；删除 App 后必须用 UT 的 `foreign_key_check` 验证新 schema 完整性。

## Source 删除规则

- `sources.userID + sources.id` 只拥有来源自身配置，以及同一用户空间的 Library 当前选择状态。
- 删除 Source 使用软删除：写入 `sources.deletedAt`，并把删除动作写入 `sync_queue`。
- 删除 Source 不删除 `rss_reading_history`、`comic_chapter_history`、`video_watch_history`。
- 删除 Source 必须在当前选择匹配时清空 `user_library_state.selectedSourceID`、`listContextJSON`、`lastRefreshAt`。
- 不删除 `users`。
- 不删除 `favorites` 或阅读历史；这些用户快照独立于来源生命周期。
