# CloudKit 阶段 0：数据合同与安全审计

- 日期：2026-07-22
- Container：`iCloud.com.xiefei.AnyPortal`
- Database：Private Database
- 首期同步对象：自定义 Source、FavoriteItem
- 状态：数据合同已确定；上传前安全门禁必须在真实 CloudKit 接线前实现

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

不能仅依赖字段名扫描。安全门禁需要理解上述结构，并允许明确的非敏感公开常量。
对于无法可靠判断的字面量，默认拒绝同步并提示用户确认或修改规则。

## 4. CloudKit Record 合同

使用一个 Private Custom Zone：

```text
BrowseCraftSync
```

CloudKit 中不保存本地 `userID`。Private Database 已按 iCloud 账户隔离；下载写入 GRDB 时，必须使用
当前已确认的 `accountScope` 绑定数据，不能信任远端 payload 提供本地身份。

### 4.1 `Source` Record Type

Record name：`source:<sourceID>`

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

### 4.2 `FavoriteItem` Record Type

Record name：`favorite:<itemID>`

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

## 6. 冲突与删除合同

- 上传必须使用 CloudKit change tag / save policy 检测服务端并发修改。
- 业务合并比较 `max(updatedAt, deletedAt)`。
- 时间相同时 tombstone 优先。
- 不能只依赖设备时间判断冲突。
- 只有服务端确认保存成功，才能移除对应 `sync_queue` 项。
- partial failure 按记录更新队列，不能整批删除。

## 7. 阶段 0 验收结果

| 检查项 | 结果 |
| --- | --- |
| 首期同步对象范围 | 已确认 |
| CloudKit Record Type 与字段 | 已确认 |
| 本地 `userID` 是否上传 | 已确认不上传 |
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
