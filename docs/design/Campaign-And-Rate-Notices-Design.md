# 活动与生成率提示

设计稿（画布，含网址输入页普通档 / 困难档 / 退回全部地区 / 全部地区也不足只给次数 / 取不到成功率 / 深色、设置页「活动推送」关 / 深色开 / 系统通知被关 / 未登录、
活动弹窗浅色与深色 App 上、新注册欢迎页（均为卡片模板）、锁屏活动推送，共 14 张）：[活动与生成率提示](https://claude.ai/artifact/6krDDFMgGhVrgLhFXRkDXP)；
设计文档：[活动与生成率提示设计书](https://claude.ai/artifact/J3NzxhSg1grTQmCgzq442M)。
设计与实施状态见 [STATUS.md](../STATUS.md)。颜色、圆角、字号与交互约定沿用网址输入页与设置页
（[网址输入页](Generation-Input-Page-Redesign-Design.md)、[设置页](Settings-Page-Redesign-Design.md)），App 内不新增色值。

## 一、范围

本文定义四处提示：

| 提示 | 通道 | 谁来发 | 内容从哪来 |
| --- | --- | --- | --- |
| 活动弹窗 | Firebase In-App Messaging（卡片模板），打开 App 时 | Firebase 控制台 | 控制台里录的插画与简 / 繁 / 英文案 |
| 新注册欢迎页 | 同上，App 在新注册后触发 | Firebase 控制台建一次，长期有效 | 同上 |
| 网址输入页的成功率一行 | PortalCore `GET /v1/generation-rates` | App 打开网址输入页时自己取 | 生成结局按国家 × 类型 × 档位每天汇总 |
| 锁屏活动推送 | PortalCore 直连 APNs（现有通道） | 服务器上的活动脚本 | 脚本参数里的三语文案 |

不在本文范围：预检率（不显示；预检失败不扣 coin，且预检结果只在 Firebase Analytics 里）、来源页活动横幅（不做）、
活动领取按钮（没有，coin 由服务器直接入账）。生成结果推送不变。

## 二、条款

- `BCA-UI-004` 活动类提示（活动弹窗、新注册欢迎页）的界面只由 Firebase In-App Messaging 呈现，插画与文案在 Firebase 控制台制作。
  App 不得为活动自绘弹窗、横幅或卡片，也不得替换 In-App Messaging 的默认显示组件。App 对 In-App Messaging 只做两件事：
  接入 SDK，以及在第五节约定的时机触发事件。
- `BCA-UI-005` 「活动推送」开关只决定 PortalCore 发活动推送时是否包含这台设备，状态以设备登记上的同意标记为准，默认关。
  它不控制生成结果推送，也不控制 In-App Messaging。活动推送只发给已登录、开关打开的设备。
- `BCA-SYNC-012` coin 只在 PortalCore 账本入账：活动赠送由服务器批量入账脚本发放，新户赠送在建号事务里发放。
  App、In-App Messaging 弹窗与推送都只告知，不得发起入账，也不得携带或决定赠送额度；告知必须在入账完成之后发出。

推送不接入 FirebaseMessaging：生成结果推送与活动推送都由 PortalCore 直连 APNs，App 只登记一种设备 token。

## 三、网址输入页的成功率一行

- 位置：`VideoGenerationInputView` 的「取页方式」卡片组（`SettingsCardGroup`）里，`GenerationTierPicker` 与档位说明之下。
  不新增卡片，不新增控件，页面仍只有一个主控件。
- 样式：13pt 次级色，前置 13pt 柱状图标（次级色）；百分比用主文字色 semibold，数字等宽。深色模式按现有次级色与主文字色取值。
- 文案两种，三语。{地区} 由 App 把服务端返回的两位国家码按系统语言本地化，服务端返回 `scope` 为 global 时写「全部地区」；
  {N} 取服务端返回的窗口天数。
  - 有百分比时：「{地区} · 近 {N} 天{普通模式 / 困难模式}生成成功 {百分比}」。
  - 样本不足、只有次数时（用户 2026-10-18 定）：「{地区} · 近 {N} 天{普通模式 / 困难模式}生成 {总次数} 次，成功 {成功次数} 次」。
    次数少时用户自己看得出分量，不拿小样本冒充百分比；成功次数用主文字色 semibold，数字等宽。
- 随档位切换：普通档与困难档各显示各的数，切档只换显示，不重新请求。
- 取数与显示按以下顺序，App 不上报位置、不要定位权限，地区由服务器从请求 IP 判断：
  1. `VideoGenerationInputView` 出现时发一次请求，与输入网址、检查网站并行，不等结果、不挡任何操作；整个 sheet 只取一次，切档不重新请求。
  2. `BrowseCraftAPIKit` 的新客户端经 `PortalAPIClient` 与现有公共请求头请求 `GET /v1/generation-rates?kind=video`（按当前类型），不要登录。
  3. 返回示例：`{"region":"JP","windowDays":30,"rates":{"normal":{"rate":0.64,"samples":52,"successes":33,"scope":"region"},"hard":{"rate":null,"samples":6,"successes":4,"scope":"global"}}}`。
     每档各带 `scope`、`samples`（已结束的次数）与 `successes`（成功次数），按以下顺序取一种：本地区满 20 条给本地区的数与百分比；
     不满则换成全部地区，全部地区满 20 条给百分比；全部地区也不满但至少 1 条时 `rate` 为空、只给次数；一条都没有时 `samples` 为 0。
  4. 解码成一个只在本次 sheet 状态里的小模型，不落库、不缓存。
  5. 取当前档那一项拼成一行：`rate` 有值用百分比文案，四舍五入到整数；`rate` 为空而 `samples` 大于 0 用次数文案。
  6. 请求失败、超时，或当前档 `samples` 为 0 时，这一行不显示，不弹错、不重试；请求失败只经 `AppLog` 记 `portal`（请求钩子）与 `generation`（吞错）两类日志。
     App 不估算、不写死数字。
- 组下的余额说明（`generation_input_balance_footer` 与 `generation_input_balance_unknown_footer`）已写明「生成可能失败，失败也会扣 coin」，
  档位说明文案不改。

## 四、设置页「通知」分组

- 位置：「安全」与「隐私与诊断」之间，分组标题「通知」。
- 一行 `SettingsToggleRow`，标题「活动推送」，默认关。图标新做 22pt 纯黑剪影模板图（喇叭），与其余设置图标同一规格，按资产登记纪律登记。
- 组下说明按状态取一种：
  - 正常：「活动开始时提醒你，例如送 coin。生成结果的通知不受影响，由系统设置里的通知权限决定。」
  - 系统通知被关：警示色「需要先在系统设置里允许 AnyPortal 的通知，才能收到活动推送。」后接动作蓝「前往设置」，点了打开系统设置里本 App 的页面。
    开关保持可用，值不变。
  - 未登录：行按「用不了」显示（图标块与标题变灰），开关禁用；说明「登录后可以接收活动推送。」
- 打开开关：系统通知许可尚未决定时先申请；随后经 `PushDeviceRegistrationCoordinator` 把同意标记与设备语言随设备登记同步到 PortalCore。
  关闭开关同步不同意。开关值存在本机；登出时设备照旧注销，重新登录后按本机值重新同步。
- 开关变化报 `setting_changed`，`setting_name` 为 `campaign_push`（[Analytics-Events-Design.md](Analytics-Events-Design.md) 第 3 节 H 组，`BCA-OBS-001`）。

## 五、In-App Messaging

- 接入：`project.yml` 链接 firebase-ios-sdk 的 In-App Messaging product（SPM 名带 Beta 后缀）。只用默认显示组件，不写自定义显示代码。
- 活动弹窗（控制台配置）：
  - 卡片模板：3:2 插画铺满卡片顶部，下面是标题、正文与一个文字按钮；触发为打开 App；频率为每台设备一次。
  - 配色：白底，标题与正文墨色 `#1C1C1E`，按钮文字动作蓝 `#2563EB`（卡片模板的按钮没有底色）；深色模式下也是白卡。
  - 插画：控制台在 Spark 方案下不能上传图片，只能填 HTTPS 地址；插画由 PortalCore 的 `/media/<文件名>` 提供，1200×800、纯白底，换图时换文件名。
  - 语言：In-App Messaging 的语言列表只有一个中文，默认内容写简体，英文作译文；繁体系统看到简体。
  - 投放对象：限时活动加「首次打开超过 N 天前」（N 取活动天数），避免活动开始后新装、没有入账的设备看到「已到账」。
  - 一个按钮「知道了」，不带跳转链接。
  - 文案写明「已注册账号」已入账，避免未登录用户以为自己也拿到了。
- 新注册欢迎页：同一模板与配色，按钮「开始使用」。Apple 登录完成、登录页收起后，登录接口返回 `accountCreated` 为真且
  `signupGrantCoins` 大于 0 时，App 触发 In-App Messaging 事件 `welcome_new_account`；新注册但没拿到赠送（12 个月内删号重注册）
  与老用户重新登录都不触发。
- 「传送使用统计」关闭时 In-App Messaging 照常拉取与显示，只是不报埋点（`BCA-OBS-005`）。关掉「活动推送」不影响弹窗。
  In-App Messaging 自带的展示、点击与关闭三个事件已在 [Analytics-Events-Design.md](Analytics-Events-Design.md) 第 2 节登记为 Firebase 自动事件，不经 `AppAnalytics`。
- 插画按设计索引的插画规格出图后上传到控制台。
- 中国大陆不开 VPN 的设备连不上 Google，看不到弹窗与欢迎页；coin 照常入账，以 coin 记录与活动推送为准。

## 六、锁屏活动推送

- 由服务器上的活动脚本经现有 APNs 通道发送；负载带 `kind` 为 campaign，标题与正文按设备登记的语言取三语之一。
- 只发给 `marketing_opt_in` 为真的设备；第一版不按地区筛选。
- App 收到点击时识别活动推送，刷新 `CoinWalletStore` 的余额，不跳页；报 `push_opened`，`entry` 为 `campaign`（[Analytics-Events-Design.md](Analytics-Events-Design.md) 第 3 节 A 组）。

## 七、服务端依赖（PortalCore）

本节的服务端陈述以 PortalCore 仓为准，App 仓只核得到接口路径与字段名。

| 位置 | 内容 |
| --- | --- |
| `GET /v1/generation-rates` | 不要登录、按 IP 限流；参数 `kind`；按请求 IP 的 GeoIP 国家码返回 `region`、`windowDays`（30），以及普通 / 困难两档各自的 `rate`、`samples`、`successes`、`scope`（region / global）；取值顺序见第三节第 3 步 |
| 登录接口 | `POST /v1/auth/apple` 的返回加 `accountCreated` 与 `signupGrantCoins` |
| 设备登记 | `POST /v1/push/devices` 加 `marketingOptIn` 与 `language`；登记时记 GeoIP 国家码，只存两位国家码、不存 IP |
| 生成记录 | 提交时记 GeoIP 国家码 |
| 每日汇总 | 宿主机定时任务每天把近 30 天生成结局按国家 × 类型 × 档位写进汇总表；生成率 = 成功（含合并）÷ 已结束的全部结局；不计未结束的任务、复用现成规则留下的记录、运营与测试账号、上游额度用完导致的失败。国家码上线前的任务一律不计（全部地区也不计）：那批任务都是用户自己的测试数据（用户 2026-10-18 确认）；上线后 GeoIP 判断不出国家的任务记为未知，只计入全部地区 |
| GeoIP 库 | DB-IP Lite 国家库（CC BY 4.0，免注册），放数据卷、宿主机每月更新一次；库缺失或过期时国家码记为未知、不影响生成；隐私权政策页署名 DB-IP |
| 活动脚本 | 一次活动一条命令：先给所有已注册账号幂等入账（新记账原因 `campaign_grant`，同一活动同一账号只入一次），确认完成后再按 `--push` 发活动推送；支持只报人数的预演 |

一次活动的顺序固定为：预演报人数 → 入账并报实际人数 → 控制台发布弹窗（先发测试设备确认）→ 发活动推送 → 活动结束时控制台停用。

## 八、App 实施清单

| 位置 | 内容 |
| --- | --- |
| `project.yml` | 链接 In-App Messaging product |
| 网址输入页 | 第三节的成功率一行与取数 |
| `BrowseCraftAPIKit` | 成功率接口、登录返回的两个字段、设备登记的两个字段 |
| 设置页 | 第四节的「通知」分组、图标资产与三语文案 |
| 设备登记 | `PushDeviceRegistrationCoordinator` 带上同意标记与语言 |
| 登录后 | 第五节的欢迎页触发 |
| 推送点击 | 第六节的活动推送识别与余额刷新 |
| 埋点 | 第四至六节列出的事件与取值，先登记再写代码 |
| 隐私说明 | 隐私政策写明 In-App Messaging 会把 Firebase Installation ID 发给 Google、服务端按 IP 推出国家码且不存 IP；核对 App Store 隐私标签 |
