# CloudKit 阶段 0：数据合同与安全审计

- 日期：2026-07-22
- Container：`iCloud.com.xiefei.AnyPortal`
- Database：Private Database
- 首期同步对象：自定义 Source、FavoriteItem
- 状态：数据合同已确定；上传前安全门禁必须在真实 CloudKit 接线前实现

> 2026-07-28 身份合同更新：本文关于客户端生成 AppUser UUID、`/v1/auth/register`、
> `/v1/auth/recover` 以及购买前必须关联 iCloud UUID 的内容已经失效。当前身份与购买边界以
> `AccountScopedDatabaseMigration-Memo.md` 为准；Cloud payload 安全审计结论继续有效。

## 1. 审计范围

本次沿着以下持久化和转换链路检查 Cloud payload 的实际来源：

```text
Source.configuration
→ SourceRecord.configJSON
→ SourceCloudPayload.configJSON

FavoriteContentItem
→ FavoriteItemRecord.itemJSON / sourceSnapshotJSON
→ FavoriteItemCloudPayload.itemJSON / sourceSnapshotJSON
```

同时检查了 `SourceCredential`、`InMemorySourceCredentialStore`、`RequestConfig`、
`SiteRuleContextValue`、受保护资源解密规则和资源处理 Pipeline。

## 2. 审计结论

### 2.1 当前明确不会自动进入 Cloud payload 的数据

`SourceCredential` 当前只保存在 `InMemorySourceCredentialStore`，没有实现 `Codable`，也没有被
`SourceRecord` 或 `FavoriteItemRecord` 引用。因此以下运行时登录态不会自动进入现有 payload：

- `HTTPCookie`
- credential headers
- access token / refresh token
- localStorage / sessionStorage
- credential expiration 和 origin

这只是当前实现事实。以后如果 Credential Store 改为持久化实现，仍然禁止把这些字段并入 Cloud payload。

### 2.2 当前不能直接上传的字段

`configJSON` 是完整 `SourceConfiguration`。其中的规则模型允许持久化：

- 任意 `RequestConfig.headers` 和 `imageHeaders`
- 任意 `RequestBody.value`
- `SiteRule.context` / `VideoSiteRule.context` 的字面量默认值
- 受保护资源规则中的 constant key、IV、`keyHex`、`ivHex`
- Resource Pipeline constant binding

因此，即使 Credential Store 本身安全，用户导入或编辑的规则仍可能把真实 Cookie、Authorization、
token、设备标识或静态密钥作为普通字符串写进 `configJSON`。

`FavoriteItemRecord.itemJSON` 编码的是完整 `FavoriteContentItem`，其中已经包含 `sourceSnapshot`；
同一记录又把该快照单独保存为 `sourceSnapshotJSON`。这会造成配置重复，并形成两条敏感数据传播路径。

结论：当前 `configJSON`、`itemJSON` 和 `sourceSnapshotJSON` 不能不经检查直接上传。

## 3. 安全策略

### 3.1 基本原则

- 不修改本地 Source 配置。
- 不静默删除或替换规则字段，避免同步后规则语义损坏。
- 在生成待上传 Cloud record 前执行深度检查。
- 检测到敏感字面量时，只拒绝该记录上传；保留 `sync_queue` 并记录可展示的错误原因。
- 日志和错误信息只能包含 JSON path、问题类型和 Header 名称，不能打印疑似敏感值。
- 动态 credential 引用或模板引用可以允许，但实际解析后的 credential 值绝不能写回配置或 payload。

### 3.2 必须拦截的 Header 名称

Header 名称比较忽略大小写，至少包括：

```text
Authorization
Proxy-Authorization
Cookie
Set-Cookie
X-API-Key
X-Auth-Token
X-Device-ID
Device-ID
```

名称包含 `token`、`secret`、`password`、`credential`、`device`、`uuid`、`api-key` 时也按敏感项处理。

### 3.3 必须检查的非 Header 路径

- `context.*.value`
- `context.*.default`
- `context.*.anonymousValue`
- `context.*.userValue`
- 任意 Request Body 字面量
- `ProtectedResourceValueRule` 中 `source == constant` 的 `value`
- `ProtectedResourceContextSecretDerivationRule.keyHex`
- `ProtectedResourceContextSecretDerivationRule.ivHex`
- `ResourceBindingRule` 中 `source == constant` 的 `value`
- `baseURL`、`detailURL`、`coverURL`、业务 ID 及 JSON 内嵌 URL 中的 userinfo
- URL query 中静态 token、signature、authorization、credential、Cookie、Session、Password、API key 等敏感值
- Favorite source snapshot 任意层级中符合本地格式的 `cloud:<64 hex>` account scope

不能仅依赖字段名扫描。安全门禁需要理解上述结构，并允许明确的非敏感公开常量。
对于无法可靠判断的字面量，默认拒绝同步并提示用户确认或修改规则。
动态模板引用可以保留；错误只报告字段路径和 query 名称，不包含 URL 或 query value。

### 3.3 记录大小预算

- 不能只分别限制 JSON 字段；必须按整条 CloudKit record 的所有字符串字段合计。
- 当前实现为 CloudKit 固定开销预留 8 KB，并将可上传记录总预算限制为 900 KB。
- 单个 JSON 仍保留 800 KB 上限；超限时拒绝单条上传，不截断业务数据。

## 4. CloudKit Record 合同

Identity 与内容同步使用不同 zone：

```text
Private Database / default zone
└── AppUserIdentity/default

Private Database / custom zone: BrowseCraftSync
├── Source
└── FavoriteItem
```

Source/Favorite Cloud payload 中不保存本地 `userID`。Private Database 已按 iCloud 账户隔离；
下载写入 GRDB 时，必须绑定到当前已确认的 `ActiveAppUser.id` UUID。`CloudAccountScope` 只用于同步
队列、游标和账户世代，不能再写入业务记录的 `userID`，也不能信任远端 payload 提供本地身份。

### 4.1 `AppUserIdentity` Record Type

用户主动点击 iCloud 关联按钮后才读取或创建该记录；App 启动不得自动关联、自动切换 UUID
或自动执行 Portal 登录恢复。

客户端基础合同已落地：

- `CloudAppUserIdentity` 是不依赖 CloudKit SDK 的身份值模型。
- `CloudAppUserIdentityRecordContract` 集中维护 record type、record name 和字段名。
- `CloudAppUserIdentityStoring` 只提供读取和“缺失时创建”，不提供可覆盖既有 UUID 的通用保存接口。
- 并发创建时，Adapter 必须返回 CloudKit 中最终存在的权威记录，交由后续手动关联状态机比较 UUID。
- `CloudAppUserIdentityAssociationState` 只描述用户主动关联流程，不能由 App 启动自动推进。
- `CloudKitAppUserIdentityStore` 已注入 AppContainer，但只由设置页关联按钮或用户主动开启
  Cloud Sync 的身份门禁调用。
- Adapter 只使用传入 `CKContainer` 的 `privateCloudDatabase`，record ID 未指定 custom zone，
  因而固定落在 default zone。
- 创建使用 `ifServerRecordUnchanged`；并发冲突或服务端响应丢失时重新读取权威记录，不覆盖 UUID。
- 下载严格校验 record type、record ID、UUID、schemaVersion 和时间字段，不接受畸形身份记录。
- `CloudAppUserIdentityAssociationCoordinator` 只暴露用户主动关联入口；App 生命周期不调用。
- 设置页提供独立的 `Link BrowseCraft Identity` 操作；刷新 iCloud 状态不会读取 Identity。
- Cloud Sync 开启流程必须先通过 Identity 关联，再显示内容合并选择或启用既有分区。
- UUID 不同时只产生单一冲突状态并保持同步关闭，等待用户选择合并本地数据、仅使用云端
  Profile 或取消。
- 用户确认后两种数据选择都采用云端 UUID B；合并只复制本地业务内容并保留 A，
  `useCloudDataOnly` 不复制 A。
- 采用过程不复制 AppUser 权益字段和 StoreKit 交易；Portal Keychain item 原子覆盖为
  B 的 `recoveryRequired` 空凭证状态，不调用 Portal 网络接口或 StoreKit。

```text
zone: default zone
recordType: AppUserIdentity
recordName: default
```

| 字段 | CloudKit 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userID` | String | 是 | 当前 iCloud 数据空间关联的 BrowseCraft UUID |
| `schemaVersion` | Int64 | 是 | 首版为 1 |
| `createdAt` | Date | 是 | 首次关联时间 |
| `updatedAt` | Date | 是 | 最近确认时间 |

该记录不保存 Portal Access/Refresh Token、StoreKit JWS、Apple ID、邮箱、设备标识或 recovery secret。

### 4.2 `Source` Record Type

Record name：`source:<SHA256(canonical sourceID)>`

| 字段 | CloudKit 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `schemaVersion` | Int64 | 是 | 首版为 1 |
| `sourceID` | String | 是 | 业务稳定 ID |
| `name` | String | 是 | 展示名称 |
| `baseURL` | String | 是 | Source 基础 URL |
| `type` | String | 是 | 当前 SourceType raw value |
| `kind` | String | 是 | runtime kind |
| `configJSON` | String | 是 | 仅允许通过安全门禁的完整配置 |
| `enabled` | Int64/Bool | 是 | 本地启用状态 |
| `createdAt` | Date | 是 | 创建时间 |
| `updatedAt` | Date | 是 | 最近业务更新时间 |
| `deletedAt` | Date | 否 | tombstone；非空表示软删除 |

约束：

- `built-in.*` 不上传。
- 旧 schemaVersion 或不支持的视频 V1 配置不写回本地。
- payload 超过 CloudKit 单记录安全容量时拒绝上传，不自动截断 JSON。

### 4.3 `FavoriteItem` Record Type

Record name：`favorite:<SHA256(canonical sourceID + itemID)>`

收藏的业务主键为 `(sourceID, itemID)`；不同 Source 可以合法地产生相同 GUID/link。原始 ID 保存在字段中，
record name 只使用固定长度 ASCII 摘要，避免 URL、Unicode 或超长业务 ID 违反 CloudKit 标识约束。

| 字段 | CloudKit 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `schemaVersion` | Int64 | 是 | 首版为 1 |
| `itemID` | String | 是 | 收藏业务稳定 ID |
| `sourceID` | String | 是 | 所属 Source ID |
| `kind` | String | 是 | FavoriteContentKind raw value |
| `title` | String | 是 | 标题 |
| `detailURL` | String | 是 | 详情 URL |
| `coverURL` | String | 否 | 封面 URL |
| `latestText` | String | 否 | 最新信息文本 |
| `itemMetadataJSON` | String | 是 | 不包含 sourceSnapshot 的收藏补充字段 |
| `sourceSnapshotJSON` | String | 否 | 仅允许通过同一安全门禁的 SourceSnapshot |
| `favoritedAt` | Date | 否 | 收藏时间 |
| `updatedAt` | Date | 是 | 最近业务更新时间 |
| `deletedAt` | Date | 否 | tombstone；非空表示软删除 |

`itemMetadataJSON` 只保存当前独立字段未覆盖的内容，例如：

- `idCode`
- 内容自身的 `updatedAt`
- `listOrder`
- `listContext`

它不能再次包含 `sourceSnapshot`。从 Cloud 下载后，由 typed fields、`itemMetadataJSON` 和已经验证的
`sourceSnapshotJSON` 重新构造本地 `FavoriteContentItem` / `itemJSON`。

## 5. 明确排除的数据

以下数据不得进入首期 CloudKit schema：

- Cookie、Authorization、token、登录凭证
- localStorage、sessionStorage
- 实际 AES key、IV 和其他密钥材料
- 图片、网页、音视频缓存
- 阅读进度和历史记录
- 内置 Source
- StoreKit 交易、购买凭证和权益状态
- CloudKit opaque user record ID 的原文
- 本地 account scope hash

## 5.1 iCloud 与内购关联边界

购买和恢复只绑定同一个 BrowseCraft UUID：

```text
AppUserIdentity.userID
== Portal Access JWS sub
== StoreKit transaction.appAccountToken
== PortalCore purchase owner
```

- 客户端在用户点击购买或 `Restore Purchases` 后验证 `AppUserIdentity.userID` 与活动用户一致。
- 未关联 iCloud 或 UUID 不一致时，在调用 StoreKit/PortalCore 前阻断。
- `AppStore.sync()` 只能由用户点击 `Restore Purchases` 触发；启动、前台恢复和 iCloud 关联不得触发。
- 采用 CloudKit UUID 时不得把旧 UUID 的 Portal credentials、权益字段或
  `user_storekit_transactions` 复制给新 UUID。
- 免费用户采用 B 后可以没有 Portal session；客户端不得因为 session 缺失自动调用购买恢复。
- PortalCore 无权访问 CloudKit Private Database，因此 CloudKit UUID 比较属于客户端门禁。
- PortalCore 继续负责验证 `sub/request.userId/appAccountToken` 以及原始交易 owner 唯一性。

### PortalCore 接口审计

已只读审计 PortalCore 提交 `36dbbd7d048ae33acfabc4452a53c133e02bbd14`：

- `/v1/auth/recover` 只恢复既存 AppUser，验证单笔购买 JWS 与 `appAccountToken`，成功后创建 session。
- `/v1/iap/entitlements/refresh` 要求 Bearer Token，并强制 `sub == request.userId`。
- IAP service 强制每笔 Apple `appAccountToken == request.userId`。
- `(environment, originalTransactionId)` purchase owner 唯一约束会拒绝跨 UUID 重复认领。

因此现有后端满足 Portal/StoreKit/owner 部分，不需要为当前规则新增接口；客户端仍必须实现
手动 iCloud 关联和恢复前 CloudKit UUID 门禁。该提交尚未部署，生产 `6111fc7` 不能视为已提供这些接口。

客户端 APIKit 已实现 `/v1/auth/recover` 与 `/v1/iap/entitlements/refresh` DTO、请求大小校验、
Bearer 发送和稳定错误映射。AppContainer 只装配服务，不在启动、前台或 iCloud 关联时调用；
StoreKit JWS 仍只能由后续用户主动购买/恢复状态机提交。

## 6. 冲突与删除合同

- 上传必须使用 CloudKit change tag / save policy 检测服务端并发修改。
- 业务合并比较 `max(updatedAt, deletedAt)`。
- 时间相同时 tombstone 优先。
- 不能只依赖设备时间判断冲突。
- 只有服务端确认保存成功，才能移除对应 `sync_queue` 项。
- partial failure 按记录更新队列，不能整批删除。
- 同步调度以 `CloudSyncCoordinator` 为唯一入口；CKSyncEngine 关闭自动调度，避免自动发送与 GRDB 队列确认形成两套状态机。
- Zone deletion 必须清除持久化 engine state 与 record system fields；普通删除和 encrypted-data reset 从有效本地数据重建队列，用户主动 purge 则清理本地 cloud scope 缓存且禁止重传。

## 7. 阶段 0 验收结果

| 检查项 | 结果 |
| --- | --- |
| 首期同步对象范围 | 已确认 |
| CloudKit Record Type 与字段 | 已确认 |
| 本地 `userID` 是否上传 | 仅 `AppUserIdentity/default` 保存；Source/Favorite payload 不保存 |
| Credential Store 是否自动进入 payload | 当前不会 |
| `configJSON` 是否可直接上传 | 不可，必须增加安全门禁 |
| Favorite JSON 是否存在重复快照 | 存在，必须拆分 `itemMetadataJSON` |
| 敏感数据失败策略 | 拒绝单条上传并保留队列 |
| 日志脱敏原则 | 已确认 |

## 8. 后续实现前置条件

阶段 4 的真实 CloudKit Adapter 开始上传前，必须具备：

1. `CloudSyncPayloadSecurityValidator` 或等价的结构化安全检查组件；
2. Source、Favorite 两条 payload 路径共用同一套规则；
3. Favorite `itemJSON` 去除重复的 `sourceSnapshot`；
4. 对敏感 Header、context literal、Request Body、constant key/IV 的单元测试；
5. 错误与日志不包含原始敏感值。
