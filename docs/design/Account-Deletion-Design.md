# 删除账号（App 侧）

设计与实施状态见 [STATUS.md](../STATUS.md)。服务端的数据处置、接口合同与失败代码定义在 PortalCore 仓库的
删号设计稿（`docs/architecture/2026-10-15-account-deletion-design.md`，第 3–10 节），本文只写 App 侧：入口与流程、
服务端确认删除后本机与 iCloud 的清理、换访客身份、未完成清理的续做、Apple 凭据状态监听与失败文案。
依据是 App Store 审核指南 5.1.1(v) 与 Apple 技术说明 TN3194。

## 一、范围与裁决

用户五项裁决（服务端设计稿 D1–D5）在 App 侧的落点：

| 裁决 | App 侧做什么 |
| --- | --- |
| D1 服务端删账号记录与个人数据 | App 只调接口，不参与服务端数据处置 |
| D2 删号时重新做一次 Apple 验证，现取授权码 | 删号流程里先取 challenge，再做一次 Sign in with Apple，把 identityToken、nonce、authorizationCode 一起交给删号接口 |
| D3 不重复发注册赠送 | App 不涉及 |
| D4 删号释放内购归属，可在新账号恢复 | 说明页写明可恢复；恢复购买的本地筛选见第九节 |
| D5 本机与 iCloud 的数据都删 | 第五、六节 |

## 二、入口

设置页最下方「退出登录」卡片下面加一行次级红字「删除账号」，只在已登录时显示。它不是卡片，是一行居中的文字按钮，
视觉权重低于退出登录。点击推入「删除账号」说明页（`AccountDeletionView`），不是弹框：内容放不下。

## 三、说明页

说明页分四组，自上而下：

1. **将删除**：账号与登录信息；coin 余额 N（已登录时显示服务端余额），删除后作废、无法恢复；生成记录；
   本机与 iCloud 中由本 App 存储的来源、收藏、历史、阅读进度与导入的书。
2. **将保留**：你生成过的站点规则会保留，已与你断开，供其他用户复用。
3. **已购项目**：已购项目跟随 App Store 账户；删除后用同一 App Store 账户重新登录，在购买页点「恢复购买」即可找回；退款向 Apple 申请。
4. **进行中的生成**：会继续完成，但你看不到结果，也收不到通知；已扣的 coin 不退。

底部一个红色主按钮「继续」。点击后弹系统居中提示框（`.alert`），不用 confirmationDialog——iOS 26 上它变成指向按钮的气泡
（2026-10-03 裁定，与退出登录一致）。提示框标题「删除账号？」，说明「删除后无法恢复」，按钮「取消」与红色「删除账号」。

## 四、删除流程

确认后由 `AccountDeletionCoordinator` 串行执行：

1. 取 Portal 访问令牌（`PortalSessionCoordinator` 的 `validAccessToken()`，临近过期会先刷新）。取不到即「登录已失效，请重新登录后再删除」。
2. `POST /v1/auth/apple/challenge` 取 nonce。
3. 用该 nonce 做一次 Sign in with Apple，得到 `AppleSignInAuthorization`（identityToken、authorizationCode、Apple user 标识）。
   用户在系统界面取消 → 回到说明页，什么都不提示。
4. 持久化「删除进行中：UUID」标记（第七节），然后 `POST /v1/account/deletion`（Bearer，body 为 identityToken、nonce、authorizationCode）。
5. 服务端回 200：执行第五、六节清理与换身份，显示完成页。回其他：清掉进行中标记，按第八节提示「账号未删除」。

第 4–5 步期间显示全屏进度遮罩「正在删除账号…」，不可取消：遮罩吞掉点击，返回按钮与侧滑返回都禁用。

服务端约定：nonce 在核对 Apple ID 之后即被消费，授权码只能用一次，因此任何失败后的重试都从第 2 步重来；App 不自动重试。

## 五、服务端确认删除后的本机清理与换身份

顺序固定，先换身份再删旧数据——旧用户的行被删时它已经不是活动用户，任何仓储都不会再为它读写：

1. `CloudSyncCoordinator.prepareForIdentityChange()`：取消进行中的 CloudKit 操作，等本轮固定 UUID 的同步退出。
2. 清 Keychain 里的 Portal 会话（只清本地，不再调注销接口——服务端会话已随账号删除）；权益缓存随第 6 步的用户行删除。
3. 生成新访客 UUID，在数据库补一行 `users`，写进 Keychain 身份存储（`KeychainAppUserIdentityStore`），再 `ActiveAppUserStore.update`。
   这与首次安装时 `AppUserIdentityBootstrapper` 做的事相同。
4. `CoinWalletStore.markSignedOut()`。
5. 删 Keychain 里保存的 Apple user 标识（第十节）。
6. 删旧 UUID 名下的本机数据（`GRDBAccountDeletionLocalDataStore`，一个写事务）：
   - 先读出该 UUID 关联过的 iCloud 分区（`cloud_app_user_association_attestations` 与 `cloud_account_partition_preparations`），
     删这些分区的 `sync_state`、`cloud_record_metadata`、`sync_queue`——即重置 CKSyncEngine 状态与同步队列；
   - 再删 `users` 里该 UUID 的行。来源、收藏、三张历史表、临时资源历史、库状态、续看账本、本地书、阅读进度、书签、
     StoreKit 交易明细与两张分区表都外键级联到 `users`（GRDB 默认开外键），随之删除；
   - 事务前读出该 UUID 的本地书文件与封面相对路径，事务提交后逐个删文件。文件删除失败不回滚：书已不在书架，残留文件只占空间，
     与 `DeleteLocalBookUseCase` 的取舍相同。
7. 第六节的 iCloud 清理。

第 6 步失败（数据库错误）时保留「待清本机：UUID」标记，下次启动与回到前台时重试；完成页提示「账号已删除；本机数据将在下次打开 App 时自动清除」。
连续失败到第三次时改为提示「请删除并重新安装 App 以清除本机数据」。

## 六、iCloud 清理

### 6.1 归属判定

服务端设计稿第 7 节最初写的是「删 zone `BrowseCraftSync` 中 `userID` 等于被删 UUID 的记录」，已按本节改正。核对代码：
云端 `Source` / `FavoriteItem` / `HistoryEntry` 记录**没有 userID 字段**（`CloudKitRecordMapper` 写入的字段里没有它，
记录名也只由来源 ID、条目 ID 等算出），App 读回时把本地活动用户填进去。同一个 iCloud 账户只承载一个业务账号：
`AppUserIdentity/default` 记着它，同步前 `CloudSyncCoordinator` 按本机关联证明核对活动用户与之相同才放行（`BCA-SYNC-004`）。

所以「属于被删账号的 iCloud 数据」按 zone 整体判定：

| `AppUserIdentity/default` | 处理 |
| --- | --- |
| 存在且 userID 等于被删 UUID | 删 zone `BrowseCraftSync`，再删 `AppUserIdentity/default` |
| 存在且 userID 是别的账号 | 这个 iCloud 承载的是别的账号的数据，不动 |
| 不存在 | 本机关联证明（第五节第 6 步事务前读出、随待清标记保存）表明当前 iCloud 分区曾关联被删 UUID 时删 zone；否则不动 |

只有本次读到的 `AppUserIdentity/default` 指向被删 UUID 时才删它；zone 本来就不存在（从没开过同步）算删成。

### 6.2 iCloud 不可用

iCloud 账户状态不是可用（未登录 iCloud、本 App 的 iCloud 被关、受限）或请求失败（断网、配额、服务暂不可用）时，
本机清理照常完成，同时持久化「待清 iCloud：UUID + 关联过的分区」，在启动、回到前台、网络恢复时重试，成功才清标记。

完成页提示：「iCloud 中的数据将在连接 iCloud 后自动清除。如果你关闭了本 App 的 iCloud，可以手动删除：
设置 → [你的名字] → iCloud → 管理储存空间 → AnyPortal → 删除数据。」
App 区分不了「没登录 iCloud」和「关了本 App 的 iCloud」（账户状态同为不可用），两句一起给。

## 七、未完成工作的续做

`UserDefaultsAccountDeletionPendingWorkStore` 保存一份 `AccountDeletionPendingWork`：

| 字段 | 含义 | 何时清 |
| --- | --- | --- |
| 删除进行中 | 已发出删号请求、结果未知的 UUID | 拿到任何响应后 |
| 待清本机 | 服务端已删、本机数据未删净的 UUID | 第五节第 6 步成功 |
| 待清 iCloud | 服务端已删、iCloud 未清的 UUID 与关联过的分区 | 第六节成功，或判定不属于该账号 |

启动、回到前台、网络恢复时 `AccountDeletionCoordinator.resumePendingWork()` 依次处理：

- **删除进行中**（请求发出后 App 被杀或切后台超时）：用当时的会话调 `GET /v1/account`。401 说明账号已删除 → 按第五节执行；
  200 说明没删 → 清标记；网络错误 → 留着下次再判。删号请求是原子的，不会出现删了一半。
  该会话 401 也可能是被别处 logout-all 了，那时会误删本机数据；只有用户发起过删号且请求中途被杀才会走到这里，接受这个代价。
- **待清本机 / 待清 iCloud**：重做第五节第 6 步 / 第六节。

### 7.1 已知局限

同一账号同时登录在另一台设备上时，那台设备的会话会在下次刷新时被服务端拒绝而回到未登录，但它的本机数据不会被删，
已开的云同步按本机关联证明仍可能把数据传回 iCloud。删号的承诺范围是「发起删除的这台设备与 iCloud」，完成页与说明页不对其他设备作承诺。

## 八、失败与文案

原则（服务端设计稿第 10 节）：账号没删的，提示里都要明确说「账号未删除」；删了的，先说「账号已删除」再说剩下的事。

| 成因 | 已删除 | 提示 |
| --- | --- | --- |
| 用户取消 Apple 验证 | 否 | 不提示，回到说明页 |
| 系统 Apple 登录失败 | 否 | 账号未删除。无法完成 Apple 验证，请稍后重试。 |
| 401 会话类（`AUTH_REQUIRED` 等）或取不到访问令牌 | 否 | 账号未删除。登录已失效，请重新登录后再删除。 |
| 401 验证类（challenge / identityToken 过期或无效）、400 授权码失效 | 否 | 账号未删除。验证已过期，请再试一次。 |
| 403 Apple ID 不一致 | 否 | 账号未删除。你验证的 Apple ID 与当前登录的账号不一致。 |
| 503 Apple 服务不可用 | 否 | 账号未删除。Apple 服务暂时不可用，请稍后重试。 |
| 503 服务端未配置 | 否 | 账号未删除。服务暂时无法删除账号，请稍后重试。 |
| 500 删除事务失败 | 否 | 账号未删除。删除未完成，账号未受影响，请稍后重试。 |
| 429 | 否 | 账号未删除。操作太频繁，请稍后再试。 |
| 发出请求前网络错误（取 challenge 失败） | 否 | 账号未删除。网络连接失败，请检查网络后重试。 |
| 请求发出后没拿到可判读的响应（断网、超时、无错误信封的 5xx、200 解码失败） | 未知 | 当场用 `GET /v1/account` 探一次：401 按已删除走完成页；200 提示账号未删除；探不出则提示「无法确认是否已删除，网络恢复后会自动确认」，标记留给第七节续做 |
| 其他 4xx / 解码失败 | 否 | 账号未删除。删除未完成，请稍后重试。 |
| 200 + `revoke_failed` | 是 | 完成页附：请到 设置 → [你的名字] → 登录与安全 → 通过 Apple 登录 → AnyPortal → 停止使用。 |
| iCloud 待清 | 是 | 完成页附第 6.2 节文案 |
| 本机清理失败 | 是 | 完成页附第五节文案 |

「账号未删除」的提示用系统居中提示框，留在说明页，用户可以再点「继续」。
「已删除」一律进完成页：标题「账号已删除」，下面按需附上述说明，底部「好」返回设置页（此时是访客状态，账号卡显示「用 Apple 登录」）。

## 九、恢复购买的本地筛选

D4 依赖服务端放行「appAccountToken 指向的账号已不存在」的交易（PortalCore 删号设计稿第 6.2 节与第 14 节第 3、4 条；
购买、更新、恢复三条路径共用同一个权益刷新接口，例外对三条都生效）。App 原先在本地就按 appAccountToken 等于当前账号筛交易，
删号后在新账号点「恢复购买」找不回任何东西。服务端的批量校验遇到「token 指向的账号仍然存在」的交易会整批拒绝，
所以 App 侧不能把外来 token 的交易并进本账号那一批。用户裁定（2026-10-15）送审前做完，做法如下。

### 9.1 恢复购买

`SettingsViewModel` 的恢复路径收齐可恢复的已验证交易后，交给 `StoreKitRestoreBatchPlanner` 分批：

| 批 | 内容 | 失败时 |
| --- | --- | --- |
| 本账号批 | appAccountToken 等于当前账号的交易 | 照旧整体报错 |
| 外来批（每个 token 一批） | appAccountToken 是别的 UUID 的交易 | 服务端回 `IAP_ACCOUNT_MISMATCH`（那个账号仍然存在）或 `IAP_TRANSACTION_ALREADY_CLAIMED`（已被另一个账号认领）时跳过该批，计入「属于别的账号」；其他错误照旧整体报错 |
| 不提交 | 没有 appAccountToken 的交易 | 计入「属于别的账号」 |

先提交本账号批，再逐个提交外来批；只 finish 成功提交的交易。服务端每次回的都是当前账号的完整权益，取最后一次成功的结果。
所有批都不同环境时照旧拒绝（同一次恢复只认一个 StoreKit 环境）。

恢复后购买页提示「部分购买属于另一个账号」的判据，从「存在外来 token 的已拥有交易」改为「存在外来 token、且该商品不在服务端回的权益里的已拥有交易」——
被新账号认领成功的旧账号购买不再算作别人的。

### 9.2 购买页

- 购买前发现该商品已被这个 App Store 账户拥有：不论交易的 token 是不是当前账号，都提示「已经购买过，请用『恢复购买』同步权益」；
  没有 token 的仍提示没有绑定到当前账号。旧账号已删除时，恢复购买按 9.1 认领；旧账号仍在时，恢复后提示属于另一个账号。
- 购买完成后 StoreKit 交回的交易若带外来 token（非消耗型重买时 App Store 交回原交易），不在本地拦截，提交给服务端判定；
  `PortalPurchaseCoordinator` 的购买提交只要求 token 存在。

### 9.3 不改的路径

交易更新监听（`AppContainer` 收到的 StoreKit 交易更新，经 `PortalPurchaseCoordinator` 的更新提交）仍要求 token 等于当前账号：
被认领的旧账号交易发生退款时，服务端经 App Store 服务器通知自行处理（服务端设计稿第 14 节第 3 条），App 不必为它多发请求。

## 十、Apple 凭据状态

- Apple 登录成功（登录与删号重新验证都算）后，把 Apple user 标识存进 Keychain（`KeychainAppleUserIdentifierStore`，
  与业务身份同一 service、不同 account，仅本机、首次解锁后可读）。退出登录不删它：同一台设备下次登录会覆盖。
- 启动与回到前台时，已登录且存有 Apple user 标识的，调 ASAuthorizationAppleIDProvider 的 getCredentialState；
  同时监听 credentialRevokedNotification。状态为 revoked 或 notFound 时按退出登录处理：清 Portal 会话与权益缓存、
  `CoinWalletStore.markSignedOut()`，**不删任何本地数据**（`AppleCredentialRevocationCoordinator`）。
- 存量已登录用户没有存过 Apple user 标识，跳过检查，下次登录后生效。
- 查询失败、或状态为 authorized / transferred 时不做任何事。
- **只认「见过正常之后的撤销」**：每次 Apple 授权成功（保存 Apple user 标识）都把「这次授权后见过 authorized」清零；
  之后系统回过一次 authorized 才记为见过。revoked / notFound（无论来自状态查询还是撤销通知）只有在见过之后才按退出处理，否则只记日志。
  依据是模拟器实测：删号撤销授权后用同一 Apple ID 重新登录，授权后 1 秒、133 秒、154 秒、775 秒 getCredentialState 一直回 revoked；
  直接按状态退出会把刚登录的新账号反复退出去，10 分钟宽限也挡不住。代价是状态一直卡在 revoked 的用户真被撤销时不会被 App 自动退出，
  服务端会话照旧受控。标记与授权时间同 Apple user 标识一起存在 Keychain（`KeychainAppleUserIdentifierStore`，
  值为「标识|保存时的 Unix 秒|0 或 1」）；每次检查都记下系统回的状态与距授权的秒数。
- 自动退出后通知设置页刷新登录状态（`AppleCredentialRevocationCoordinator` 的 `didSignOut`，由 `AppContainer` 接上）。

## 十一、实现落点

| 层 | 新增或改动 |
| --- | --- |
| APIKit | `PortalAPIPath.accountDeletion`；`PortalAccountAPI.deleteAccount`；`PortalAccountDeletionRequest`（无 schemaVersion，多字段服务端回 400）、`PortalAccountDeletionResponse` |
| Application 端口 | `AppleSignInAuthorizing` 返回 `AppleSignInAuthorization`；`AppleUserIdentifierStoring`；`AppleCredentialStateChecking`；`PortalAccountDeleting`；`AccountDeletionLocalDataStoring`；`AccountDeletionCloudDataErasing`；`AccountDeletionPendingWorkStoring` |
| Application | `AccountDeletionCoordinator`（流程、清理、换身份、续做）；`AppleCredentialRevocationCoordinator`；`PortalSessionCoordinator` 加只清本地会话的入口；`PortalAppleSignInCoordinator` 登录成功后存 Apple user 标识 |
| Infrastructure | `AuthenticationServicesAppleSignInAuthorizer` 同时取 authorizationCode 与 user；`KeychainAppleUserIdentifierStore`；`AuthenticationServicesAppleCredentialStateChecker`；`APIKitPortalAccountDeletionService`；`GRDBAccountDeletionLocalDataStore`；`CloudKitAccountDeletionCloudEraser`；`UserDefaultsAccountDeletionPendingWorkStore` |
| Features | 设置页「删除账号」行；`AccountDeletionView` 与 `AccountDeletionViewModel`（说明页、确认框、进度遮罩、完成页） |
| App | `AccountComposition` 装配；`AppContainer` 启动与回到前台时续做未完成工作、检查 Apple 凭据状态 |
| 文案 | en / zh-Hans / zh-Hant 三语 |

验证：构建通过加静态自核；`AccountDeletionCoordinator` 的清理顺序、换身份、续做标记，与 `GRDBAccountDeletionLocalDataStore` 的删除范围写单测。
真机验证由用户做（服务端第 12 节第 6 步）。
