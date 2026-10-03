# 缓存页的视觉与信息结构重设计

设计稿（画布，含浅色 / 深色、正在计算、正在清除、清除完成，共 5 张）：
[缓存页重设计](https://claude.ai/artifact/Mhf86nzg1QS9LBuSecPDHQ)；设计文档：[缓存页重设计](https://claude.ai/artifact/Vz1g6TnRcupR5uNLiPSfXu)。
设计与实施状态见 [STATUS.md](../STATUS.md)。颜色、圆角、字号与交互约定沿用设置页与 coin 记录页
（[设置页](Settings-Page-Redesign-Design.md)、[coin 记录页](Coin-Ledger-Page-Redesign-Design.md)）。

## 一、背景

`CacheSettingsView` 曾是一个系统 `Form`：一组「图片缓存上限」单选加一个红色「清除缓存」。

- 这是设置里的二级页，底栏仍在。
- 看不到缓存已用多少，也就不知道该不该清。
- 「清除缓存」只清封面与漫画页那一块，列表缩略图、网页与系统网络缓存都没清；清完只弹一个「已开始清除」提示框。
- 外观是系统分组列表，图标颜色与文字颜色不一致。

## 二、本机有哪些缓存

| 缓存 | 放什么 | 上限 | 是否在本页清除 |
| --- | --- | --- | --- |
| 封面与漫画页 | 封面、详情头图、漫画阅读器页面、书的封面 | 本页所选 512 MB / 1 GB / 2 GB | 清 |
| 列表缩略图 | 库页网格、收藏与历史卡片里的小封面 | 固定 256 MB | 清 |
| 网页缓存 | 规则页渲染、网页播放器、登录页的页面资源 | WebKit 自管 | 只清磁盘、内存与 fetch 缓存 |
| 系统网络缓存 | 网络请求的默认 HTTP 缓存 | 系统自管 | 清 |

以下是用户数据，清除缓存时不得碰：数据库里的来源与规则、收藏、历史与阅读进度、书签、coin；导入的书文件；
网页的 Cookie 与本地存储（来源登录状态在这里）；钥匙串。

读书阅读器没有写到磁盘上的缓存：章节正文按规则即时取、即时排版，只在内存里；书的目录在内存里留 5 分钟；
有声书边下边播；书的封面已在封面缓存里；导入的本地书是用户文件。所以本页不设「书籍」一项。
将来若做离线下载章节，下载的内容属于用户数据，在书的详情页管理，不进本页的清除。

## 三、导航与信息结构

- 从设置页「同步与存储 › 缓存」推入，隐藏底栏，左上系统返回是唯一出口（2026-10-03 用户裁定），导航栏居中小标题「缓存」。
- **用量卡**：小字「图片缓存已用」，大数字两块合计，后面写「/ 最多 768 MB」（所选上限 + 缩略图固定 256 MB）；
  下面两条用量条「封面与漫画页 已用 / 上限」「列表缩略图 已用 / 256 MB · 固定」。用量在缓存自己的队列上读磁盘计算，算好前显示「正在计算」。
  网页缓存的大小 WebKit 不提供可靠的字节数，不显示。
- **上限**：分组标题「封面与漫画页上限」，三行 512 MB / 1 GB / 2 GB，每行右侧小字写两块合计最多占用（768 MB / 1.25 GB / 2.25 GB），
  选中行尾蓝色 ✓。组下说明「上限只管封面与漫画页，列表缩略图另有固定的 256 MB」加原有的自动清理说明。
  两块分开计、缓存行为不变，只把显示写清楚让数字对得上（2026-10-03 用户裁定）；缩略图的 256 MB 保持固定，不交给用户选（同日裁定）。
- **清除**：单独一张卡片「清除缓存」，删除色居中；组下一句「不会删除来源、收藏、历史、阅读进度、导入的书和登录状态。」

## 四、清除与其余状态

- 点「清除缓存」不弹确认（2026-10-03 用户裁定）：清掉的只是下次会重新下载的东西。
- 清除一起清封面与漫画页、列表缩略图、网页缓存（磁盘、内存、fetch）与系统网络缓存（同日裁定），磁盘真正清完才算完成。
- 清除中按钮换成转圈 +「正在清除」并禁用；清完用量重算，按钮下绿色一行「已清除，释放 N」约 3 秒后消失。N 只算图片部分。
- 改上限时 ✓ 立刻移到新行；新上限小于已用时按原有逻辑裁到新上限的 75%，裁完重算用量。
- 保存上限失败仍弹原有提示框，文案不变；去掉原来「已开始清除」那个提示框。
- 页面跟随系统深浅，只用系统底色层级与 `CatalogPalette` 的取值。

## 五、实现位置

- `BrowseCraft/Features/Settings/Cache/CacheSettingsView.swift`：隐藏底栏、用量卡与两条用量条、上限卡片组、清除卡片与清除结果、保存失败提示框。
- `BrowseCraft/Features/Settings/SettingsViewModel.swift`：用量（`ImageCacheUsage`，nil 为正在计算）、清除中、释放了多少。
- `BrowseCraft/Application/Ports/Settings/ImageCacheManaging.swift`：取用量与全部清除两个主 actor 上的异步动作。
- `BrowseCraft/Domain/Models/Settings/ImageCacheSettings.swift`：`ImageCacheUsage`。
- `BrowseCraft/Infrastructure/Caching/ImageCacheConfigurator.swift`：在 DataCache 自己的串行队列上算用量、清除并等待完成。
- `BrowseCraft/Infrastructure/Caching/ItemThumbnailImageCachePlugin.swift`：暴露缩略图磁盘缓存与固定上限，补清内存。
- `BrowseCraft/Infrastructure/Caching/WebsiteCacheCleaner.swift`：只清 WebKit 的缓存类数据。
- 三份 `Localizable.strings` 末尾「缓存页重设计」一段。
