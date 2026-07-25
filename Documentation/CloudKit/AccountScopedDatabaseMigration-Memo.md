# Identity 数据归属与数据库策略备忘

更新时间：2026-07-25
状态：Identity 数据归属收口已接线；不提供旧开发数据库升级

## 当前决定

`AppUser.id` UUID 是唯一业务 `userID`。Source、Favorite、History、Library 和 StoreKit
记录全部归属于该 UUID。

`CloudAccountScope` 不是业务用户，只用于隔离：

- CloudKit 同步队列
- change token
- CKSyncEngine state
- CKRecord metadata
- 云账户首次绑定决策与账户世代

CloudKit 下载的业务数据在落库时绑定当前 `ActiveAppUser.id`，不会把
`CloudAccountScope.rawValue` 写入业务表的 `userID`。

## 数据库策略

当前仍处于可删除 App 重建数据库的开发阶段，因此：

- `AppDatabase` 只创建最终 schema。
- App 启动时不创建 `local.default`。
- Keychain 身份 bootstrap 读取或生成 UUID，再幂等创建对应 `users` 记录。
- 不实现 `local.default -> UUID` 升级迁移。
- 不兼容已经把 `cloud:<hash>` 写入业务 `userID` 的旧开发数据库。
- `cloud_record_metadata.accountScope` 和
  `cloud_account_partition_preparations.accountScope` 不引用 `users.id`。

需要验证新 schema 时，删除 App 后重新安装。隔离测试若仍依赖旧身份 fixture，可以显式插入
`local.default`，但该路径不得进入 App Composition Root。

## 当前边界

- 业务 owner：`ActiveAppUserProviding.currentUserID`
- 同步 partition：`ActiveAccountScopeProviding.currentScope`
- Portal API `userId`：活动 UUID
- Source/Favorite Repository：活动 UUID
- Source/Favorite Cloud sync 本地落库：活动 UUID
- Queue/state/token/metadata：CloudAccountScope

CloudKit `AppUserIdentity/default` 将放在 Private Database 的 default zone。它只在用户点击
iCloud 关联按钮后读取或创建；App 启动不自动关联、不自动切换 UUID，也不自动恢复 StoreKit
交易或 Portal 登录。购买和恢复前由客户端确认 CloudKit UUID 与活动 Portal 用户一致。

当前已完成不依赖 CloudKit SDK 的 Identity 基础合同：

- 身份模型和 schema 字段常量
- 手动关联状态枚举
- 只读/缺失时创建的存储协议
- 禁止通用覆盖既有云端 UUID 的接口边界
- Private Database default-zone Adapter
- 并发创建冲突后读取云端权威 UUID
- record type、record ID、schemaVersion、UUID 和时间字段的严格映射
- 仅由用户动作触发的 Identity 关联协调器
- 设置页独立关联按钮和 Cloud Sync 开启前身份门禁
- UUID 冲突的单一阻断状态

Adapter 和手动关联状态机已注入 AppContainer。App 启动、App 恢复前台和普通 iCloud 状态刷新
不会读取 `AppUserIdentity/default`；只有独立关联按钮或用户主动开启 Cloud Sync 才会读取/创建。
UUID 冲突进入单一确认 Sheet。用户选择 `mergeLocalData` 或 `useCloudDataOnly` 后都会采用
CloudKit UUID B；取消则保持 A。合并会在一个 GRDB 事务内把 A 的 Source、Favorite、
History、Library State 和临时资源历史复制到 B，并保留 A；云端优先不会复制 A 的内容。

身份采用绝不复制 A 的 AppUser 权益字段或 `user_storekit_transactions`。Keychain 身份和活动
用户切到 B 后，Portal Keychain item 原子覆盖为 B 的 `recoveryRequired` 空凭证状态。
该流程不调用 Portal register/recover，不调用 StoreKit；旧 Portal session 也不能供 B 复用。

StoreKit 的 `AppStore.sync()` 只允许由内购页面的 `Restore Purchases` 按钮触发。

## 静态验证重点

- 新数据库创建后不会自动出现 `local.default`。
- Identity bootstrap 后只存在活动 UUID 用户。
- CloudAccountScope 变化不会改变 Source/Favorite 的业务 owner。
- 同步队列和同步状态继续按 CloudAccountScope 隔离。
- Cloud payload 落库时统一重绑到活动 UUID。
