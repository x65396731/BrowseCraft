# 收藏与历史的面容 ID 锁定

设计稿（画布，含设置页浅色与深色、打开开关时的验证、触控 ID 设备 / 只有锁屏密码 / 没有锁屏密码三种设备变体、
收藏与历史的锁定态、深色锁定态、只有锁屏密码的设备的锁定态、切过来自动拉起验证、取消或未通过验证，共 12 张）：
[收藏与历史 · 面容 ID 锁定](https://claude.ai/artifact/YLh1CUu4QBxrPYvkmnTN43)。设计与实施状态见 [STATUS.md](../STATUS.md)。
颜色、圆角、字号与行样式沿用设置页、收藏页与历史页（[设置页](Settings-Page-Redesign-Design.md)第四节、
[收藏页](Favorites-Page-Redesign-Design.md)、[历史页](History-Page-Redesign-Design.md)），本功能不新增色值。

## 一、背景

收藏和历史记着用户看过、想看的内容，手机借给别人或被旁人拿起时，这两页一点开就全部露出来。
本功能让用户在设置页打开一个开关，之后进入这两页前要先通过面容 ID（或触控 ID、锁屏密码）验证。

一个开关同时锁收藏和历史（2026-10-17 用户确认设计稿），不按页分开设置。

## 二、设置页的开关

### 2.1 位置与行

- 设置页在「同步与存储」与「隐私与诊断」之间新增「安全」分组，只有一行开关（`SettingsToggleRow`），组下一段说明（`SettingsCardGroup` 的 footer）。
- 默认关闭。开关只存在本机（`UserDefaultsContentLockPreferenceStore`），不随 iCloud 同步；与登录无关，未登录也显示。

### 2.2 随设备变化的标题、图标与说明

验证方式取系统 LocalAuthentication 的设备所有者验证策略（deviceOwnerAuthentication）：先用生物识别，不过时可转锁屏密码。行的写法随设备能用的方式变：

| 设备 | 行标题 | 图标 | 组下说明 |
| --- | --- | --- | --- |
| 面容 ID | 面容 ID 锁定 | `SettingsFaceID` | 开启后，进入「收藏」和「历史」前要先通过面容 ID 验证，验证不了时可以输入锁屏密码。离开 AnyPortal 后会重新锁定。 |
| 触控 ID | 触控 ID 锁定 | `SettingsTouchID` | 同上，「面容 ID」换成「触控 ID」 |
| 光学 ID | Optic ID 锁定 | `SettingsOpticID` | 同上，换成「Optic ID」 |
| 只有锁屏密码 | 密码锁定 | `SettingsPasscode` | 开启后，进入「收藏」和「历史」前要先输入锁屏密码。离开 AnyPortal 后会重新锁定。 |
| 没有锁屏密码 | 密码锁定（禁用） | `SettingsPasscode` | 这台设备没有设置锁屏密码，暂时不能开启。在系统「设置」里设置密码后再回来打开。 |

四张图标是 22pt 模板图，与设置页其他行同一规格（SF Symbol faceid / touchid / opticid / lock.fill 栅格化，登记资产预算）。

判断顺序（`LocalAuthenticationDeviceOwnerAuthenticator`）：

1. 先问设备所有者验证策略能不能用。不能用，即连锁屏密码都没有：没有锁屏密码。
2. 能用，再问只用生物识别的策略。能用，或只是被系统暂时锁住（输错太多次，之后会恢复）：按硬件类型取面容 ID / 触控 ID / 光学 ID。
3. 否则（没有生物识别硬件，或有硬件但没录入）：只有锁屏密码。

设置页每次出现、App 每次回到前台都重新判一次，用户在系统设置里补设密码或录入面容后回来即生效。

「只有锁屏密码」与「没有锁屏密码」标题都是「密码锁定」，靠外观与说明区分：

| | 图标块 | 标题 | 开关 |
| --- | --- | --- | --- |
| 可用（含只有锁屏密码） | 添加蓝底与图标，同设置页其他行 | 主文字色 | 可点 |
| 没有锁屏密码 | 系统填充色底、三级文字色图标 | 次级文字色 | 禁用，由系统压暗 |

### 2.3 打开与关闭都要先验证

- 打开前验证一次：确认这台设备真能验证，验证通过的同时视为已解锁，切到收藏或历史不再立刻要求验证。
- 关闭前也验证一次：防止别人拿到已解锁的手机后直接关掉。
- 验证通过才改开关；取消或失败时开关保持原状态，不弹提示框。
- 设备没有锁屏密码时开关禁用。已经打开后设备又删掉了锁屏密码：开关显示为关闭、禁用，两页直接可看，免得用户被永久锁在外面；
  存下的开启状态保留，重新设好密码后自动恢复锁定。

## 三、锁定态

`ContentLockedView` 是收藏页与历史页共用的锁定态：

- 页面只保留自绘大标题，隐藏右侧数量、类型筛选、继续卡片与列表——条数本身也算隐私。没有收藏或没有历史时同样显示锁定态，不透露「是否为空」。
- 中间从上到下：88pt 圆标（添加蓝 12% 底、深色 24%，与设置页图标块同色）里放验证方式的图标；标题「收藏已锁定 / 历史已锁定」；
  一句说明「验证身份后查看你的收藏 / 查看最近看过的内容」；实心添加蓝胶囊按钮「使用面容 ID 解锁」（高 50，随设备换成触控 ID / Optic ID / 密码）。
- 验证进行中：按钮换成转圈 +「正在验证」并禁用，系统面容 ID 浮层盖在页面中央。
- 取消或未通过：按钮上方一行警示色小字「没有通过验证，可以再试一次」，不弹提示框；再点按钮重新验证。
- 底栏照常可切换。锁定态盖在整页之上，连同已推入的详情页、阅读器一起盖住，解锁后回到原处。
- 历史页全屏打开的视频播放器在锁定态之上，不被盖住：播放中进入后台再回来，播放器照常显示，关掉播放器后才看到锁定态。

## 四、何时锁与解锁

- 收藏与历史共用一个解锁状态（`ContentLockStore`）：解开其中一页，切到另一页不再验证。
- App 进入后台即重新锁定。
- 进入非活跃状态（多任务切换器、控制中心）时两页立刻盖上锁定态，切换器的缩略图不露内容；没进后台就回来，盖层撤掉，不要求重新验证。
  验证本身会让 App 短暂变为非活跃，验证进行中不盖。
- 切到锁定的一页时自动拉起一次验证；App 回到前台且当前停在这两页之一时也自动拉起一次。用户取消后停在锁定态，不再自动拉起，直到下次切进来或回到前台。
- 面容 ID 的重试、转锁屏密码、被系统暂时锁住，都由系统界面处理；App 只区分「通过」与「没有通过」。

## 五、不在范围内

- 只锁这两页的浏览。库页封面上的爱心、详情页的收藏按钮、播放与阅读写入历史、库页「上次看到」瓷砖照常工作。
- 不改收藏与历史的数据、同步与 iCloud；不提供「清空」之类的新入口。

## 六、实现位置

- `BrowseCraft/Application/Privacy/ContentLockStore.swift`：开关、解锁状态、非活跃盖层、验证动作、可用的验证方式。
- `BrowseCraft/Application/Ports/Settings/DeviceOwnerAuthenticating.swift`：验证端口 `DeviceOwnerAuthenticating` 与开关存储端口 `ContentLockPreferenceStoring`。
- `BrowseCraft/Infrastructure/Security/LocalAuthenticationDeviceOwnerAuthenticator.swift`：LocalAuthentication 适配器 `LocalAuthenticationDeviceOwnerAuthenticator`。
- `BrowseCraft/Infrastructure/Preferences/UserDefaultsContentLockPreferenceStore.swift`：开关的本机存储。
- `BrowseCraft/Features/Shared/ContentLockedView.swift`：两页共用的锁定态。
- `BrowseCraft/Features/Settings/SettingsView.swift`：「安全」分组。
- `BrowseCraft/Features/Favorites/FavoritesView.swift`、`BrowseCraft/Features/History/HistoryView.swift`：锁定时换成锁定态。
- `BrowseCraft/App/RootView.swift`：切标签与回到前台时自动拉起验证，进入后台与非活跃时通知 `ContentLockStore`。
- `BrowseCraft/Info.plist` 与三份 `InfoPlist.strings`：面容 ID 用途说明；三份 `Localizable.strings` 末尾「收藏与历史锁定」一段。

## 七、真机验收清单

- 设置页「安全」分组：打开与关闭都先验证，取消时开关不变；触控 ID 设备与没有锁屏密码的设备的写法。
- 收藏与历史锁定态：切过来自动拉起面容 ID，通过后两页都可看；取消后的警示小字与再试一次。
- 回到桌面再回来要求重新验证；多任务切换器缩略图不露内容；拉下控制中心再收起不要求验证。
- 关闭开关后两页直接可看；库页爱心与详情页收藏照常。深色模式看一遍锁定态。
