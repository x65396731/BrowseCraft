# 数据库说明

BrowseCraft 当前仍处于开发阶段。数据库层优先保持“当前最终 schema”清晰可读，暂时不维护生产式增量迁移兼容。

## 文件组织

- `AppDatabase.swift` 只负责数据库路径、迁移注册、表创建顺序和索引创建顺序。
- 每张表的字段、主键、唯一键和索引放在对应的 `*Record+Schema.swift`。
- `Records/User` 保存用户、权益和用户级 UI 状态。
- `Records/Source` 保存站点来源配置。
- `Records/Favorite` 保存收藏快照。
- `Records/History` 保存 RSS、漫画、视频历史快照。
- `Records/Sync` 保存 iCloud 同步游标和本地待上传队列。
- `Records/Temporary` 保存临时发现资源历史。

## 当前规则

- `favorites` 是用户级聚合表：每个 `userID` 一行，内部用 JSON 保存 RSS / 漫画 / 视频收藏快照，并保存一份派生 ID 列表用于快速判断收藏状态。
- `favorites` 和阅读历史只关联 `users`，不直接外键关联 `sources`，避免删除来源时误删独立用户快照。
- `sources` 当前未 user-scoped；如果未来要多用户同步，需要先决定是否给 `Source` 领域模型和仓储 API 增加 `userID`。

## Source 删除规则

- `sources.id` 只拥有来源自身配置，以及通过 `sourceID` 关联的 Library 当前选择状态。
- 删除 Source 使用软删除：写入 `sources.deletedAt`，并把删除动作写入 `sync_queue`。
- 删除 Source 不删除 `rss_reading_history`、`comic_chapter_history`、`video_watch_history`。
- 删除 Source 必须在当前选择匹配时清空 `user_library_state.selectedSourceID`、`listContextJSON`、`lastRefreshAt`。
- 不删除 `users`。
- 不删除 `favorites` 或阅读历史；这些用户快照独立于来源生命周期。
