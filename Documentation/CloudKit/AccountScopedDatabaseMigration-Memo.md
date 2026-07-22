# Account-scoped 数据库迁移备忘

更新时间：2026-07-22
状态：仅记录，当前不启用

## 当前决定

BrowseCraft 尚处于允许清除开发数据的阶段。阶段 3 将 Source、Favorite、同步队列和同步状态改为按
`local.default` / `cloud:<hash>` 隔离后，开发设备通过删除 App 重建数据库，不兼容此前的开发数据库。

因此当前 `AppDatabase` 直接创建最终 schema，不注册 account-scoped 兼容迁移。每次 schema 发生不兼容
变更后，需要删除 App 再安装，并通过数据库 UT 检查主键、唯一键和外键完整性。

## 暂不采用的迁移做法

此前的 `AccountScopedSyncMigration` 使用以下方式处理旧开发数据库：

1. 用 `PRAGMA table_info` 检查目标表是否仍为旧结构。
2. 将旧表重命名为临时表。
3. 按最终 schema 创建新表。
4. 使用 `INSERT ... SELECT ...` 复制旧数据，并补充 `local.default` account scope。
5. 将旧同步队列 ID 改为 `<accountScope>|<entityType>:<entityID>`。
6. 删除临时表。

该方案曾覆盖：

- `sources`：把主键从 `id` 改为 `userID + id`；
- `sync_queue`：增加 `accountScope` 并更新唯一键与队列 ID；
- `sync_state`：增加 `accountScope` 并更新复合主键。

## 为什么当前不启用

- 该实现只重建已知三张表，不是通用的外键迁移机制。
- SQLite 重命名或重建父表时，需要逐项确认所有引用表、触发器和索引，未来新增外键后不能直接复用旧实现。
- 当前业务表没有声明指向 `sources` 的数据库外键；现有业务外键主要是 `userID -> users.id`，但正式迁移仍需验证完整依赖图。
- 在允许删除 App 的开发阶段，保留未经完整迁移测试的兼容代码风险高于直接重建最终 schema。

## 正式发布前的恢复条件

开始保留用户数据后，不再允许依赖删除 App。届时应使用 GRDB 的版本化迁移机制，并至少完成：

1. 盘点 `PRAGMA foreign_key_list`、索引和触发器。
2. 为每个 schema 版本定义可重复、事务化的迁移步骤。
3. 明确迁移期间的外键处理，并在事务结束前执行 `PRAGMA foreign_key_check`。
4. 使用包含真实旧版本结构和数据的 fixture 执行升级 UT。
5. 覆盖迁移成功、事务回滚、重复启动及异常数据处理。
6. 在发布候选版本上验证升级安装，不能只验证全新安装。

## 当前 UT 验证范围

- 全新数据库的 `sources` 主键必须是 `userID + id`。
- 全新数据库执行 `PRAGMA foreign_key_check` 必须无结果。
- Source、Favorite、同步队列和同步状态必须按账户隔离。
- 首次合并不得删除或改写 `local.default` 数据。
