# 设置页的视觉与信息结构重设计

设计稿（画布，含浅色 / 深色已登录与未登录、登录中、广告加载中与诊断码已复制、退出确认框，共 7 张）：
[设置页重设计](https://claude.ai/artifact/FmfnByLQ9nJTDcEkkYdDBv)；设计文档：[设置页重设计](https://claude.ai/artifact/Bwr6e6mkxMTjZ5T6muft6m)。
设计与实施状态见 [STATUS.md](../STATUS.md)。颜色、圆角、字号与交互约定沿用来源页、规则目录页、收藏页与历史页
（[来源页](Sources-Page-Redesign-Design.md)、[规则目录页](Catalog-Page-Redesign-Design.md)第三节、[收藏页](Favorites-Page-Redesign-Design.md)、
[历史页](History-Page-Redesign-Design.md)），本页不新增色值。

## 一、背景

`SettingsView` 曾是一个系统 `Form`，与重设计后的另外四页并排在底栏时反差明显，它紧挨历史页，切换时最容易看出来：

- 「账号」一组塞了八行不同性质的东西：退出登录、coin 余额、账号 ID、云同步、书签、高级版、启动广告服务、测试版 IDFA。
- 退出登录是第一行，点了立刻退出、没有确认。
- 行的颜色按控件类型而不是按含义：Button 行标题是蓝色，NavigationLink 行是黑色。
- coin 余额与「看完一次激励广告 +N」分在相隔五行的两处。
- 账号 ID 是一整行被截断的 UUID，只在报给运营时才用。
- 书签是空壳页，只有两句说明。
- 诊断占三行，其中「诊断码」与「复制诊断码」做的是同一件事。

本页只重做设置主页。云同步、缓存、coin 流水三个子页照旧，下一轮再按同一语言重做（2026-10-03 用户裁定）；
内购页的固定深色是既有例外，不动。

## 二、信息结构

从上到下：

| 顺序 | 区 | 内容 |
| --- | --- | --- |
| 1 | 顶部 | 大标题「设置」，`largeTitle` heavy 靠左，在内容里自绘，隐藏系统导航栏 |
| 2 | 账号卡 | 见第三节 |
| 3 | 高级版 | 一张入口卡片（`SourcesEntryCardView`：48pt 添加蓝方图标 + 「高级版」+「更多来源位置与付费功能」+ ›），点开内购页；与来源页「更多位置」打开的是同一页。不带来源位置用量条（2026-10-03 用户裁定） |
| 4 | 同步与存储 | 云同步（右侧：开启 / 关闭 / 检查中 / 需要登录 iCloud 等）、缓存（右侧：上限） |
| 5 | 隐私与诊断 | 发送崩溃诊断（开关）、诊断码（点一下复制）；组下保留诊断报告包含与不包含什么的说明 |
| 6 | 关于 | 版本、给 AnyPortal 评分、账号 ID（仅登录时） |
| — | 测试工具 | 仅 `BROWSECRAFT_AD_TEST_TOOLS` 构建：「测试设备 IDFA」单独一组 |
| 7 | 退出登录 | 单独一张卡片，未登录时不显示 |

分组标题 `footnote` semibold 次级色，左右页边距 20pt。账号 ID 放在「关于」：它与诊断码一样是报给运营时才用的标识。

## 三、账号卡

账号卡是卡片色底、圆角 18 的卡片，不用深色色块——账号不是内容类型，页面设计索引约定深色只以类型色块出现。

### 3.1 已登录

- 上半：44pt 圆形图标（添加蓝底 + `person.fill`）、「AnyPortal 账号」、小字「已通过 Apple 登录」。
- 中间：小字「coin 余额」，下面大数字余额 + 小字「coin」；余额未知时大数字写「—」。右侧实心添加蓝胶囊「看广告 +N」，高 44pt，
  +N 取服务端下发的 `CoinPricing` 的 `adReward`，拿不到正数时只写「看广告」。
- 底部：「coin 流水 ›」推入 `CoinLedgerView`，进入时余额一并向服务端对齐。

「看广告」就是原来的「启动广告服务」，动作不变（`AdPlaybackViewModel` 带奖励协调器播放）；它和余额放在一起，看完就在旁边看到数字变化。

### 3.2 未登录

- 左侧是本页自己的插画 `SettingsSignIn`：看板娘双手递出一张发光的空白通行证，按 66×108pt 显示。
  规则目录页「我的生成·未登录」的 `CatalogPersonalSignIn` 不借用——同一个人物同一张图出现在两页，会让两处空状态读成同一件事。
- 右侧标题「登录 AnyPortal 账号」、说明「购买、云同步和 coin 都需要登录」，下面是系统「通过 Apple 登录」按钮
  （`AppleSignInButton` 包一层 `ASAuthorizationAppleIDButton`，浅色黑底、深色白底）。Apple 对这个按钮的外观有要求，不自绘；
  点按仍走 `SettingsViewModel` 原来的登录动作。
- 下方保留描边胶囊「看广告」（不带 +N）与小字「未登录看完不计 coin」：未登录能看，但不计奖励（2026-10-03 用户裁定）。
  看完后的提示沿用 `AdPlaybackViewModel` 已有的未登录文案。

### 3.3 进行中

- 登录中：登录按钮换成转圈 +「正在登录」。
- 广告加载中：「看广告」按钮换成转圈 +「加载中」并禁用，卡片其他部分照常可点。
- 退出中：退出登录卡片里出现转圈并禁用，账号卡保持原样直到退出完成。

禁用态由系统压暗一层，按钮不再叠加透明度，否则深色模式下「加载中」几乎看不见。

## 四、行样式

| 元素 | 取值 |
| --- | --- |
| 卡片组 | 同组行拼成一张圆角 18 的卡片，卡片色底（`SettingsCardGroup`） |
| 行高 | 最小 52pt |
| 图标 | 32pt 圆角 9 的方块（`SettingsIconTile`）：添加蓝底，浅色 12%、深色 24%；图标为资产里的 `Settings*` 模板图，22pt 原生渲染，浅色添加蓝、深色浅蓝（`CatalogPalette` 的 `settingsIcon` 与 `settingsIconFill`，两档色值都已在该文件里） |
| 标题 | `body`，主文字色；只有退出登录是删除色，只有按钮是添加蓝 |
| 右侧说明 | `subheadline` 次级色，单行，放不下时末尾省略 |
| 尾部 | 进入子页或打开外部页的行加 ›；点了就做完的行（复制）不加 |
| 开关 | 系统 `Toggle` 默认样式（`SettingsToggleRow`） |
| 行间线 | 从 60pt 起（`SettingsRowSeparator`） |
| 按下态 | 铺一层系统填充色（`SettingsRowButtonStyle`） |
| 退出登录 | 单独卡片，文字居中、删除色 `#E5484D`，没有图标 |

## 五、点击语义

| 行 | 右侧说明 | 点了 |
| --- | --- | --- |
| 看广告 +N | — | 加载并播放激励广告 |
| coin 流水 | — | 推入 `CoinLedgerView` |
| 高级版 | 更多来源位置与付费功能 | 打开内购页 |
| 云同步 | 同步状态 | 推入 `CloudSyncSettingsView` |
| 缓存 | 上限 | 推入 `CacheSettingsView` |
| 发送崩溃诊断 | 开关 | 切换采集开关并记一次设置变更 |
| 诊断码 | 码本身 | 复制；说明换成「已复制」约 2 秒后恢复 |
| 版本 | 版本号与构建号 | 无 |
| 给 AnyPortal 评分 | — | 打开 App Store 写评价页 |
| 账号 ID | 前 8 位 + … | 复制完整 ID；说明换成「已复制」约 2 秒后恢复 |
| 退出登录 | — | 弹系统居中提示框「退出 AnyPortal 账号？」，按钮「取消」与红色「退出登录」；确认才退出，取消什么都不发生 |

确认用最普通的居中提示框，不用 iOS 26 上会变成指向按钮气泡的确认菜单（2026-10-03 用户裁定）。退出登录要确认（2026-10-03 用户裁定）：它不同于删除，退出后购买、云同步与 coin 都不可用，要重新走 Apple 登录，没法用底部撤销恢复。

其余状态：登录、广告、缓存的失败仍弹原来的提示框；打开内购页仍是全屏覆盖、隐藏底栏、无动画；
页面出现时刷新账号状态与余额，另可下拉刷新，不加刷新按钮；页面跟随系统深浅，不设 `preferredColorScheme`。

## 六、下线项

- 书签行与它的空壳页整页删除，收藏已有底栏标签；书签图标与它在资产预算表里的登记一并删除。
- 「复制诊断码」行并进「诊断码」行，长按菜单的「复制」去掉；复制图标与登记一并删除。
- 「启动广告服务」行并进账号卡的「看广告」按钮。
- 新增插画 `SettingsSignIn` 登记在资产预算表里。
- 只被以上几行使用的本地化字符串三语一起删除。

## 七、实现位置

- `BrowseCraft/Features/Settings/SettingsView.swift`：滚动页、自绘大标题、账号卡与高级版卡、三个分组、测试工具组、退出登录与确认框、复制反馈、下拉刷新。
- `BrowseCraft/Features/Settings/Components/SettingsRow.swift`：`SettingsIconTile`、`SettingsRow`、`SettingsToggleRow`、`SettingsCardGroup`、`SettingsRowSeparator`、`SettingsRowButtonStyle`。
- `BrowseCraft/Features/Settings/Components/SettingsAccountCardView.swift`：账号卡的已登录、未登录与进行中。
- `BrowseCraft/Features/Settings/Components/AppleSignInButton.swift`：系统登录按钮的包装。
- `BrowseCraft/Features/Sources/Catalog/CatalogStyle.swift`：行图标的两个颜色名。
- 三份 `Localizable.strings` 末尾「设置页重设计」一段。
