# 规则目录：同站多条来源的副标题显示入口地址（2026-09-15）

## 一、背景

sfacg 桌面分类 `tid=21` 作为新来源 `sfacg-com--list-tid-21` 发布进公共目录后，与既有「全部小说」`sfacg-com--list`
在规则目录里名字都是 `book.sfacg.com`，副标题都是「书籍 · https://book.sfacg.com/」，用户分不出哪条是哪条。
线上同形的还有「动漫嗨」：手写规则 `dongmanhi` 与生成规则 `dongmanhi-com--list-1-0-0-0` 同名同 `baseURL`。

名字来自引擎：sfacg 书站没有 `og:site_name`，跨文档公共标题段被一份下载页（标题「下载菠萝包APP」）打断，退回主机名；
即使取到「SF轻小说」，同站两条仍然同名——能区分两者的分类名「魔幻」只在 `javascript:redirect('tid',21)` 按钮上，
引擎没有通用办法把它与入口对应。用户 09-15 裁决在 App 侧处理：同站多条时副标题显示入口地址。

## 二、设计

- 目录行副标题原为「类型 · 地址」，地址对个人规则取任务入口（`/outcomes` 的 `entryURL`），对公共目录取 `baseURL`。
- 新增：公共目录里**同一主机出现两条及以上**来源时，这些来源的地址改取各自规则 `pages[]` 里第一个可展示的 `url`；
  跳过缺失与带占位符的模板（如 `?page={page}`），相对路径按 `baseURL` 补全；取不到仍显示 `baseURL`。
- 单独一条的站不变，个人规则不变。公共目录列表加载时规则已解密为本体（`importRuleJSON`），`pages` 在顶层，无需再解密。
- 不改引擎、服务器与已发布规则。

## 三、固定输入

`BrowseCraftTests/Application/VideoGeneration/CatalogSourceGroupingTests.swift`：
同主机两条各自给出入口（sfacg 全部 / tid=21）；单独一条的站 `defaultEntryURLs` 为空；相对路径 `/vodtype/1/` 补全；
模板与缺失的 `url` 跳过、没有 `pages` 返回 nil。

## 四、实现位置

- `BrowseCraft/Application/UseCases/Generation/CatalogSourceGrouping.swift`：`defaultEntryURLs`、`sameHostEntryURLs`、`ruleEntryURL`。
- `BrowseCraft/Features/Sources/SourcesViewModel.swift`：`catalogEntryURL(for:)`（个人入口优先，其次同站多条入口）。
- `BrowseCraft/Features/Sources/Catalog/CatalogSourceListView.swift`：目录行 `subtitleURL` 改用 `catalogEntryURL(for:)`。

## 五、真机验证

2026-09-15 用户真机确认：规则目录里两条 sfacg 副标题分别显示 `https://book.sfacg.com/List/` 与
`https://book.sfacg.com/List/?tid=21`，动漫嗨手写 / 生成两条也能区分。
