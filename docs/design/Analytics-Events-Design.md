# 埋点事件设计

本文是 Firebase Analytics 埋点的事件字典与采集边界，也是 `AppAnalytics.Event`、`AppAnalytics.Parameter` 与
`DiagnosticScreen` 的唯一定义点：代码里每个 case 的 `///` 中文注释与本文逐条对应。设计的讨论与裁定过程见 Claude 文档
「BrowseCraft 埋点事件审计与全覆盖设计」（https://claude.ai/artifact/9tKxLWvTiLpAbAta6dCGoe）。

上报链路：调用点 → `AppAnalytics` 的强类型方法（按本文 A–I 分组放在 `BrowseCraft/Shared/Diagnostics/AppAnalytics+*.swift`）→
参数白名单过滤 → Firebase `Analytics.logEvent`。SDK 是 FirebaseAnalyticsCore，不读 IDFA；事件按 SDK 生成的安装 ID 归并，
另以诊断支持 ID 作为用户 ID，与 Crashlytics 对得上。App 为 AdMob 接的 ATT 与 Analytics 无关。

## 1. 条款

- `BCA-OBS-001` 事件、参数与页面名的唯一定义点是本文。`AppAnalytics.Event` 与 `AppAnalytics.Parameter` 的每个 case、
  `DiagnosticScreen` 的每个 case 都必须带 `///` 中文注释，写明何时触发、带哪些参数、刻意不报什么，并在本文第 3–5 节登记；
  本文登记的每个名字也必须在代码里存在。新增或改名先改本文再改代码。闸门 A13 执行。
- `BCA-OBS-002` 参数取值只有三种：枚举（字符串原始值的 Swift 枚举，snake_case）、分桶（数量、时长、空间）、哈希（SHA-256）。
  不得上报网址、路径、查询串、作品标题、章节名、搜索词、来源名、Apple 或 Portal 账号标识、邮箱、coin 余额数值、订单号与交易 ID。
  参数键只能取第 4 节的表，`AppAnalytics.Parameter.allowed` 之外的键在上报前丢弃。
- `BCA-OBS-003` 只有 `Features`、`App` 与 `Shared` 调用 `AppAnalytics`；`Domain`、`Application`、`Infrastructure` 不得引用它。
  需要 Application 层的结果时由它返回值、上层上报，Application 因此不会间接依赖 Firebase。闸门 A13 执行。
- `BCA-OBS-004` 页面曝光只经 `.analyticsScreen(_:)` 修饰符（异步后才知道是哪一页时用 `.analyticsScreen(resolving:)`）发出，
  由修饰符背后的 `AnalyticsScreenReporter` 可见页栈统一上报，同时设置 Crashlytics 的当前页面（第 2 节）；
  业务代码不得直接调用 `logScreenView`。Info.plist 关闭 Firebase 的自动屏幕报告。闸门 A13 执行。
- `BCA-OBS-005` 设置页「发送使用统计」关闭时不上报任何事件，Firebase 自动事件（含 AdMob 写入的广告事件）一并停止；
  「关闭统计」这一动作本身也不上报，只有打开时补报一次 `setting_changed`。

## 2. 原则

- 事件名 snake_case，形如「对象_动作过去式」；只有与 Firebase 保留名撞名时才加 `bc_` 前缀（`bc_app_open`）。
  名称不超过 40 个字符、字母开头，不用 `firebase_`、`google_`、`ga_` 前缀；单个事件不超过 25 个参数，参数值不超过 100 个字符。
- 一个流程的结局用一个事件加 `result` 参数，不拆成成功、失败两个事件。
- 每个页面每次显示都报 `screen_view`，包括从下级页返回，这是 GA4 的标准口径。标签页、sheet、全屏播放与阅读都算页面，系统确认框不算。
  sheet、全屏页或盖层关闭、下层页面重新露出来时也补报一次下层页面，之后事件的 `firebase_screen` 才回到它身上。
  做法是 `.analyticsScreen` 维护一个可见页栈：页面 onAppear 入栈并上报，onDisappear 出栈；出栈的是栈顶时等一轮主线程，
  新栈顶还没报过就补报（导航返回、切标签页时下层页面自己会 onAppear，不会重报）。弹 sheet 的宿主页不用写 `onDismiss` 补报，
  sheet 里没挂 `.analyticsScreen` 的内容（例如阅读器的目录、书签）不入栈，关掉也不补报。异步才知道是哪一页的页面
  在确定前就占住栈顶但不上报，避免它下面的页面被误补报。
- 不报翻页、滚动、拖动进度条、有声书播放 / 暂停 / 快进这类高频动作；阅读与播放在关闭时报一次汇总。分页加载只在失败时报（走第 3 节 I 组）。
- 来源调试页、本地书架（入口已藏）、漫画资源网页、coin 记录、历史不可用提示页只报曝光，不报行为。
- Firebase 自己会报 `first_open`、`session_start`、`user_engagement` 等自动事件，AdMob 也会写广告曝光、点击一类事件。
  它们不经过 `AppAnalytics`，不受参数白名单约束，也不在本文登记，只受统计开关控制；作为会话与留存的口径保留。

## 3. 事件

每个事件自动附带 `app_version` 与 `build_number`，下表不再重复。括号里的类型名是 `BrowseCraft/Shared/Diagnostics/AnalyticsValues.swift`
里对应的取值枚举。

### A. 应用与会话

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `bc_app_open` | 冷启动、`configure()` 完成后报一次。`app_open` 是 Firebase 保留名，所以加 `bc_` 前缀。 | 无。 |
| `app_foregrounded` | 从后台回到前台（scenePhase 变为 active）时报；冷启动那次不报。 | 无。 |
| `app_bootstrap_failed` | 启动装配失败、进入启动失败页时报。 | error_code（装配失败在哪一步）。不报：诊断码与错误文案。 |
| `startup_finished` | 开屏动画结束、退到标签页时报，记录为什么结束。 | result（StartupOutcome）、entry（落到哪个标签页）。 |
| `screen_view` | 任一页面显示时报，含从下级页返回、盖在上面的 sheet / 全屏页关闭后重新露出；由 `.analyticsScreen(_:)` 统一发出。 | screen_name、screen_class（都取 DiagnosticScreen 的原始值）。 |
| `push_opened` | 用户点开规则生成结果推送时报；推送在前台到达不报。 | entry（固定为 rule_generation）。不报：推送内容与任务 ID。 |
| `support_info_copied` | 用户复制诊断码、账号 ID 或启动失败信息时报，用来估计求助量。 | entry（SupportInfoKind）。不报：复制的内容本身。 |

### B. 来源与规则目录

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `source_selected` | 当前来源切换成功时报，不论从哪里发起。 | content_kind、source_id_hash、entry（SourceSelectionEntry）。不报：来源名与网址。 |
| `source_added` | 从规则目录添加来源的结局：服务端返回、解密入库后报 success，任一步失败报 failed。 | content_kind、source_id_hash、entry（SourceAddEntry）、result、error_code（仅失败）。不报：来源名与网址。 |
| `source_deleted` | 删除来源的撤销窗口结束、真正提交删除时报；被撤销的不报。 | content_kind、source_id_hash、entry（SourceDeleteEntry）。 |
| `source_deletion_undone` | 用户点底部「撤销」恢复刚删的来源时报。 | content_kind、result。 |
| `source_activated` | 启用已暂停来源的结局；从收藏、历史点到暂停来源弹出的启用窗口也算。 | content_kind、entry（SourceActivationEntry）、result（SourceActivationResult）。 |
| `premium_entry_tapped` | 点任一通往购买页的入口时报，算各入口的转化。 | entry（PremiumEntry）。 |
| `catalog_item_deleted` | 在「我的生成」左滑删除个人规则或失败记录时报。 | entry（CatalogItemKind）、result。 |
| `catalog_rules_updated` | 目录规则自动更新应用完成时报；没有可更新的不报。 | trigger（CatalogUpdateTrigger）、item_count_bucket（更新了几条）、result。 |

### C. 规则生成

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `generation_kind_selected` | 添加来源页选定影视 / 漫画 / 书类型时报。 | content_kind。 |
| `generation_guide_finished` | 生成引导屏点「继续」或取消时报；回看引导关闭也报。 | entry（GenerationGuideEntry）、result（GenerationGuideResult）。 |
| `generation_preflight_started` | 用户发起一次网址预检时报。 | content_kind、input_method（PreflightInputMethod）。不报：网址。 |
| `generation_preflight_result` | 预检得出结论、抛错或被用户取消时报一次。App 挡下的入口不会到服务器，算预检通过率只能靠它。 | content_kind、preflight_status、error_code、site_host_hash。不报：网址、路径与查询串。 |
| `generation_submitted` | 滑动提交生成的结局，每次提交报一次（余额不足也在这里，取代原 `generation_insufficient_coins`）。 | content_kind、hard_mode、is_refresh、result（GenerationSubmitResult）、error_code。不报：余额与用户标识。 |
| `push_permission_result` | 提交成功后系统询问通知权限的结果。 | result（PushPermissionResult）。 |

### D. 库、搜索与站点登录

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `library_category_selected` | 库页切换分类 chip 时报。 | content_kind、source_id_hash。不报：分类名。 |
| `search_submitted` | 来源内搜索提交后、第一页结果回来时报。 | content_kind、source_id_hash、result（SearchResult）、result_count_bucket。不报：搜索词。 |
| `content_opened` | 打开作品详情页（或临时资源详情）时报，算各入口的分发量。 | content_kind、source_id_hash、entry（ContentOpenEntry）。不报：作品标题与网址。 |
| `source_login_result` | 站点登录页关闭时报结局。 | content_kind、source_id_hash、entry（SourceLoginEntry）、result。不报：账号与 Cookie。 |
| `source_logout` | 库页长按「退出登录」清掉站点凭据时报。 | content_kind、source_id_hash。 |
| `favorite_added` | 加入收藏成功时报。 | content_kind、source_id_hash、entry（FavoriteEntry）。不报：作品标题。 |
| `favorite_removed` | 取消收藏成功时报；批量取消只报一次。 | content_kind、source_id_hash（批量时不带）、entry（FavoriteEntry）、item_count_bucket。 |

### E. 阅读与播放

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `reader_opened` | 漫画或书阅读器第一次加载成功时报；换章不再重复报。 | content_kind、source_id_hash、entry（ReaderOpenEntry）。 |
| `chapter_opened` | 阅读器内进入新章节时报。 | content_kind、source_id_hash、navigation（ChapterNavigation）。不报：章节名。 |
| `reader_closed` | 离开阅读器时报一次汇总，取代逐页上报。 | content_kind、duration_bucket、item_count_bucket（本次读了几章）。 |
| `reader_bookmark_added` | 书阅读器里加书签时报；与「收藏」是两回事。 | content_kind。 |
| `reader_bookmark_removed` | 书阅读器里删书签时报。 | content_kind。 |
| `playback_started` | 视频、有声书或临时资源真正开始播放时报（视频取 `markReadyToPlay`）。 | content_kind、source_id_hash、player_type、entry（PlaybackEntry）。 |
| `playback_failed` | 播放层失败时报：直链播不出、网页播放器报提供方错误；规则解析失败仍走 I 组的诊断事件。 | content_kind、source_id_hash、player_type、error_code（PlaybackFailureCode）。 |
| `playback_completed` | 原生播放器正常播完一集、有声书播完最后一章时报。 | content_kind、player_type。 |
| `playback_closed` | 关闭播放器时报一次汇总。 | content_kind、player_type、duration_bucket。 |
| `playback_fallback_tapped` | 网页播放器失败卡上点「重试」或「用浏览器打开」时报。 | entry（PlaybackFallbackAction）。 |
| `video_line_switched` | 影视详情切换播放线路时报。 | source_id_hash。不报：线路名。 |
| `ad_points_threshold` | 积分满 100、页面要弹激励广告时报（设计书 30.8）；去广告用户不累计积分，不会产生。 | ad_trigger。 |
| `rewarded_ad_result` | 一次激励广告的结局，自动唤起与设置页手动入口共用。 | ad_trigger、ad_result（含 busy：已有广告在播而跳过）、signed_in。不报：余额与用户标识。 |
| `ad_reward_credited` | 已登录看完广告后，轮询余额的结果。 | result（AdRewardCreditResult）。不报：余额数值。 |
| `tracking_authorization_result` | 第一次播激励广告前弹出的跟踪授权（ATT）窗口关闭后报一次；状态已决定、不弹窗时不报。 | result（TrackingAuthorizationResult）。Analytics 本身不读 IDFA。 |

### F. 收藏、历史与内容锁定

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `content_filter_changed` | 收藏页或历史页切换类型筛选时报。 | screen_name、content_kind（含 all）。 |
| `selection_mode_entered` | 收藏页或历史页进入选择模式时报。 | screen_name、entry（SelectionModeEntry）。 |
| `history_deleted` | 删除历史记录成功时报；批量删除只报一次。 | entry（HistoryDeleteEntry）、item_count_bucket。 |
| `open_in_library_tapped` | 长按「在库中查看来源」时报。 | screen_name。 |
| `content_unlock_result` | 收藏 / 历史的面容 ID 解锁结局。 | trigger（ContentUnlockTrigger）、result。 |

### G. 账号、购买与删除账号

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `sign_in_result` | 通过 Apple 登录的结局。 | result、error_code。不报：Apple / Portal 账号标识与邮箱。 |
| `sign_out_completed` | 退出账号成功时报；服务端拒绝 token、Apple 凭据被撤销导致的被动退出也报。 | trigger（SignOutTrigger）。 |
| `paywall_products_loaded` | 购买页加载商品的结局。 | result（PaywallLoadResult）。 |
| `purchase_started` | 点方案、弹出 StoreKit 支付前报。 | product_id。不报：价格与订单号。 |
| `purchase_result` | 一次购买的结局，以服务端确认为准。 | product_id、result（PurchaseResult）、error_code。不报：订单号与交易 ID。 |
| `restore_result` | 恢复购买的结局。 | result（RestoreResult）。 |
| `entitlement_changed` | 后台交易更新导致权益变化时报（非用户操作）。 | result（EntitlementChange）、product_id。 |
| `account_deletion_result` | 删除账号流程的结局；在确认框点取消或「保留账号」也报。 | result、error_code。 |

### H. 设置、同步与缓存

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `setting_changed` | 用户亲手改一项设置且生效时报；使用统计开关只报「打开」（关闭后什么都不报）。 | setting_name（AnalyticsSettingName）、setting_value。 |
| `settings_link_opened` | 设置页点「评分」或「隐私权政策」时报。 | entry（SettingsLink）。 |
| `cache_cleared` | 清除图片缓存完成时报。 | size_bucket（释放的空间）。 |
| `cloud_sync_first_enable_result` | 首次启用云同步弹窗的选择与结局。 | entry（CloudSyncFirstEnableChoice）、result。 |
| `cloud_sync_run` | 一次云同步跑完时报。 | trigger（AnalyticsCloudSyncTrigger）、result。不报：同步了哪些记录。 |
| `cloud_initial_restore_result` | 登录后首次从 iCloud 恢复的结局；下拉重试的也报。 | trigger（CloudInitialRestoreTrigger）、result。 |

### I. 规则执行诊断

| 事件 | 何时触发 | 参数与不报 |
| --- | --- | --- |
| `network_request_failed` | 规则执行失败且分类器判为网络类时报；用户取消不报。 | rule_stage、error_code（RuleFailurePoint）、content_kind、source_id_hash。 |
| `parse_failed` | 规则执行失败且分类器判为解析类时报。 | 同 network_request_failed。 |

## 4. 参数

GA4 每个项目只有 50 个事件级自定义维度名额。下表除 `screen_name`、`screen_class`、`app_version`、`build_number` 四个由 GA4 内置维度承接外，其余都要在控制台注册为事件级自定义维度；新增参数先进本表。

| 参数 | 含义与取值 |
| --- | --- |
| `screen_name` | 页面名，取 `DiagnosticScreen` 的原始值。 |
| `screen_class` | 页面类，与页面名同值。必须显式传：缺省时 Firebase 取当前 UIViewController 类名，SwiftUI 的类名超过 100 字符被判无效，连页面名一起丢掉。 |
| `content_kind` | 内容类型，取 `AnalyticsContentKind`。 |
| `source_id_hash` | 来源 ID 的 SHA-256，只用来按来源去重。 |
| `site_host_hash` | 入口主机名小写后的 SHA-256。 |
| `entry` | 从哪里发起，取值随事件定义。 |
| `trigger` | 非用户点击的起因，取值随事件定义。 |
| `result` | 流程结局：通用 success / cancelled / failed，个别事件扩展。 |
| `error_code` | 失败原因，snake_case 枚举（`AnalyticsErrorCode`）。 |
| `rule_stage` | 规则执行阶段，取 `DiagnosticRuleStage`（转 snake_case）。 |
| `result_count_bucket` | 搜索结果数分桶：0 / 1_5 / 6_20 / 21_50 / 51_plus。 |
| `item_count_bucket` | 批量操作或汇总的条数分桶，档位同上。 |
| `duration_bucket` | 停留或播放时长分桶：lt_1m / 1_5m / 5_15m / 15_30m / 30_60m / 60_120m / gt_120m。 |
| `size_bucket` | 释放空间分桶：lt_10mb / 10_100mb / 100_500mb / gt_500mb。 |
| `player_type` | 播放器类型：native / web / audio。 |
| `navigation` | 换章方式：next / previous / toc / auto。 |
| `input_method` | 网址怎么来的：typed / pasted / retry。 |
| `is_refresh` | 是否「重新生成」。 |
| `hard_mode` | 规则生成提交是否选了困难模式（`BC-ACQ-071`）。 |
| `preflight_status` | 预检结论：accepted / rejected / inconclusive / error / cancelled。 |
| `ad_trigger` | 谁触发的广告：comic / video / book / audiobook / manual。 |
| `ad_result` | 广告结局：completed / skipped / unavailable / failed / busy。 |
| `signed_in` | 看广告时是否已登录（未登录看完不计 coin）。 |
| `product_id` | App Store 商品 ID。 |
| `setting_name` | 哪项设置，取 `AnalyticsSettingName`。 |
| `setting_value` | 设置的新值：true / false / 缓存上限 MB。 |
| `app_version` | 版本号，每个事件自动附带。 |
| `build_number` | 构建号，每个事件自动附带。 |

## 5. 页面

每个用户可达页面一个 `screen_name`，`DiagnosticScreen` 的原始值即上报值，Crashlytics 的当前页面键共用同一取值。

| 区域 | screen_name | 页面 |
| --- | --- | --- |
| 启动 | `startup` | 开屏动画 |
| 启动 | `bootstrap_failure` | 启动失败页 |
| 标签页 | `sources` | 来源页 |
| 标签页 | `favorites` | 收藏页 |
| 标签页 | `library` | 库页 |
| 标签页 | `history` | 历史页 |
| 标签页 | `settings` | 设置页 |
| 来源 | `catalog` | 规则目录（sheet） |
| 来源 | `add_source` | 添加来源·选类型（sheet） |
| 来源 | `entry_guide` | 生成引导屏 |
| 来源 | `generation_input` | 网址输入·生成 |
| 来源 | `source_activation` | 启用来源窗口（sheet） |
| 来源 | `source_debug` | 来源详情（只读调试页） |
| 库 | `library_search` | 来源内搜索（sheet） |
| 库 | `source_login` | 站点登录（全屏） |
| 库 | `comic_detail` | 漫画详情 |
| 库 | `comic_reader` | 漫画阅读器 |
| 库 | `video_detail` | 影视详情 |
| 库 | `video_player` | 视频播放器（全屏） |
| 库 | `book_detail` | 站点书详情 |
| 库 | `book_reader` | 书阅读器 |
| 库 | `audiobook_player` | 有声书播放 |
| 库 | `book_shelf` | 本地书架（入口已藏） |
| 收藏与历史 | `temporary_detail` | 临时资源详情 |
| 收藏与历史 | `temporary_player` | 临时资源播放器（网页 / 原生） |
| 收藏与历史 | `comic_resource_web` | 漫画资源网页 |
| 收藏与历史 | `history_unavailable` | 历史不可用提示页 |
| 收藏与历史 | `content_locked` | 收藏 / 历史的内容锁定遮罩 |
| 设置 | `purchase` | 购买页（全屏层） |
| 设置 | `cache_settings` | 缓存 |
| 设置 | `cloud_sync` | 云同步 |
| 设置 | `cloud_sync_first_enable` | 首次启用云同步（sheet） |
| 设置 | `coin_ledger` | coin 记录 |
| 设置 | `account_deletion` | 删除账号 |
