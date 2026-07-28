# Identity 数据归属与数据库策略备忘

更新时间：2026-07-28
状态：已切换到 Sign in with Apple 与后端生成 AppUser UUID

## 当前决定

`AppUser.id` 仍是 Source、Favorite、History、Library、Portal Session 和 IAP 的业务
`userID`，但永久 ID 只能来自 PortalCore 的 Sign in with Apple 响应。客户端启动时生成的本地
UUID 只允许作为登录前的临时数据空间，不能提交 `/v1/auth/**`，也不能作为 StoreKit
`appAccountToken`。

身份边界固定为：

```text
Sign in with Apple identity token
→ PortalCore Apple sub 映射
→ PortalCore 返回 AppUser UUID
→ ActiveAppUser / Portal JWS sub / request.userId / appAccountToken
```

`CloudAccountScope` 仍只隔离 CloudKit 队列、change token、CKSyncEngine state、metadata 和账户
世代。iCloud 账户与 Sign in with Apple 账户、App Store 购买账户是三个不同边界。

## 登录与本地数据

- App 启动不再调用 `/v1/auth/register`。
- Keychain 中的 Portal Session schema 为 v2，只保存后端 UUID 和配套 Access/Refresh Token。
- 无 Session 或旧 schema 进入 signed-out；用户通过设置页、购买或恢复购买动作触发 Apple 登录。
- 首次 Apple 登录返回不同于临时本地 UUID 的后端 UUID 时，可复制 Source、Favorite、History、
  Library 和临时资源数据到后端用户空间。
- 复制过程不得迁移 `hasRemovedAds`、Source Slot 权益或 `user_storekit_transactions`。
- Apple 登录返回不同 AppUser 时必须清除旧账户内存权益，并重新从 Portal 获取新账户权益。

## CloudKit 关联

CloudKit `AppUserIdentity/default` 只能记录已经通过 Portal 登录的后端 AppUser UUID：

- 未登录不能创建或关联该记录。
- 云端 UUID 与当前 Portal AppUser 一致时允许启用同步。
- UUID 不一致时阻断同步，并要求用户通过 Sign in with Apple 切换到对应账户。
- 禁止通过“采用 CloudKit UUID”获得 Portal Session 或 IAP 权益；持有 UUID 不构成认证。

## StoreKit 与恢复购买

- 购买和 Restore Purchases 都必须先有有效 Portal Session。
- `Product.purchase` 使用后端 UUID 作为 `appAccountToken`。
- 恢复购买只调用 `AppStore.sync()` 和 `/v1/iap/entitlements/refresh`。
- `/v1/auth/recover` 已移除，交易 JWS 不能签发 Portal Session。
- `appAccountToken` 不匹配当前 Portal AppUser 的交易不得自动转移。

## 开发期旧数据

后端本次不迁移旧 Identity/IAP 数据。旧客户端 UUID、旧 Portal Token 和旧 CloudKit Identity
不能静默复用。开发环境可清理 App、CloudKit development 数据和旧 StoreKit 测试交易；若存在
真实生产购买，必须先设计服务端迁移，不能直接发布该身份切换。
