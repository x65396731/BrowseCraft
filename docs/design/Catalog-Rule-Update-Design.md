# 规则目录：已添加来源跟随目录自动更新

## 一、背景

从规则目录添加来源时，`AddCatalogSourceUseCase` 把规则复制一份存进本地来源库；此后书架上的列表、详情、正文与播放
都执行这份本地副本，不再读目录。服务器上的规则变了（例如 biquhua 补上分页模板与章内分页），目录列表每次打开都是新的，
本地副本却不会自己变。删掉重加能拿到新规则，但删除来源会连阅读历史与库状态一起删。

推荐内容由服务器给，App 内规则一律只读（`BCA-UI-003`），本地副本不可能被用户改过——因此本地副本应当跟随服务器，
不需要用户手动确认。个人生成的规则已经按这条原则由 `refreshPersonalSourcesFromOutcomes` 自动覆盖；
公共目录添加的来源与它采用同一原则。

## 二、设计

- **判据**：`SourcesViewModel.catalogSourceHasRuleUpdate(_:)`——把目录条目按本地来源的 `createdAt / updatedAt / enabled / origin`
  物化，比较名称、站点地址与 `configuration`；不同即「有更新」。不比较时间戳：目录接口的 `updatedAt` 没进 `CatalogSource` 模型，
  且本地 `updatedAt` 是保存时刻，两者不可比；规则本体相等才是「没变」的唯一可靠判据。物化失败按无更新处理。
- **动作**：`SourcesViewModel.applyCatalogRuleUpdates(_:)` 对目录里每条「已添加且有更新」的条目走**同一条添加路径**
  （`AddCatalogSourceUseCase` 同 id 分支：保存新规则，`createdAt / enabled / origin` 与阅读历史不动，不重新验证列表），
  `preserveSelection` 为真——不把用户从正在看的来源上拽走。目录里未添加的条目不会被顺手加进来。
- **时机**：
  - 规则目录页每次呈现与下拉刷新（`refreshCatalogSources`），读完目录立即应用；
  - App 启动读完本地来源后，与每次回到前台时，`syncAddedSourcesWithCatalog` 在后台静默读一次目录再应用。
    它不置加载态、失败只记日志不弹错；距上次成功读取不足 `catalogSyncMinimumInterval` 时跳过，
    免得来回切 App 反复拉整份目录。目录页的读取不受该间隔限制。
- **可倒查**：每次覆盖成功记一条 `catalog-sources-updated`（带条数），覆盖失败按来源记 `catalog-source-update-failed`；
  失败的来源保留旧规则，下次读取目录时重试。
- **界面**：目录行没有「更新」按钮；已添加的来源只显示「已添加」。

## 三、固定输入

- `SourcesViewModelTests.catalogSourceWithNewerRuleOffersAnUpdateAndAppliesItInPlace`：本地为 `biquhua-catalog`，
  目录同形 → 无更新；目录为 `biquhua-catalog-next`（多 `content.next`）→ 有更新；覆盖后本地规则含 `next`、`createdAt` 不变。
- `SourcesViewModelTests.addedSourcesFollowTheCatalogWithoutATap`：`applyCatalogRuleUpdates` 对已添加的来源直接覆盖，
  对未添加的目录条目不做任何事。

## 四、实现位置

`BrowseCraft/Features/Sources/SourcesViewModel.swift`（判据、应用与后台跟随）、`BrowseCraft/App/RootView.swift`（启动与回到前台的触发）、
`BrowseCraft/Features/Sources/Catalog/CatalogSourceListView.swift`（目录行只剩添加 / 添加中 / 已添加 / 添加失败）。
