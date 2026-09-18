# 规则目录：已添加来源的「更新规则」入口（2026-09-14）

## 一、背景

规则在服务器上更新（例如 biquhua 09-14 补上分页模板与章内分页）后，已添加过该来源的用户拿不到新版本：
`SourcesViewModel.refreshCatalogSources` 只重拉目录列表；规则目录里「已添加」那一行没有任何动作；
本地规则只在 `AddCatalogSourceUseCase` 遇到同 id 再添加时才会覆盖。用户唯一的办法是删掉重加，而删除来源会连阅读历史与库状态一起删。

## 二、设计

- **判据**：`SourcesViewModel.catalogSourceHasRuleUpdate(_:)`——把目录条目按本地来源的 `createdAt / updatedAt / enabled / origin`
  物化，比较名称、站点地址与 `configuration`；不同即「有更新」。不比较时间戳：目录接口的 `updatedAt` 没进 `CatalogSource` 模型，
  且本地 `updatedAt` 是保存时刻，两者不可比；规则本体相等才是「没变」的唯一可靠判据。物化失败按无更新处理，交给添加路径报错。
- **入口**：目录行在「已添加 + 有更新」时把「已添加」换成「更新」按钮（`arrow.triangle.2.circlepath`）；点击走**同一条添加路径**
  （`AddCatalogSourceUseCase` 同 id 分支：保存新规则，`createdAt / enabled / origin` 不动，不重新验证列表）。
  更新完留在目录页，让那一行变回「已添加」；首次添加仍关闭目录页回到库。
- **不做**：目录刷新时静默覆盖本地规则——用户看不见发生了什么，出问题无从倒查；先给显式入口，量到需求再考虑自动。

## 三、固定输入

`SourcesViewModelTests.catalogSourceWithNewerRuleOffersAnUpdateAndAppliesItInPlace`：本地为 `biquhua-catalog`，
目录同形 → 无更新；目录为 `biquhua-catalog-next`（多 `content.next`）→ 有更新；更新后本地规则含 `next`、`createdAt` 不变。

## 四、实现位置

`BrowseCraft/Features/Sources/SourcesViewModel.swift`（判据）、`BrowseCraft/Features/Sources/Catalog/CatalogSourceListView.swift`（行与动作）、
`Localizable.strings` 的 `catalog_update_rule`。
