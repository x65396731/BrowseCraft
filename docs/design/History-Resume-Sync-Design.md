# 续看位置同步到 iCloud

设计文档：[续看位置同步到 iCloud 设计书](https://claude.ai/artifact/4kDHGwzvSabB5VxYv6Tqpt)。设计与实施状态见 [STATUS.md](../STATUS.md)。
同步的通用规则（冲突检测、合并、队列、调度）见 [身份归属与数据库策略](AccountScopedDatabaseMigration-Memo.md) 的 `BCA-SYNC-008` ~ `BCA-SYNC-011`，
本文只写续看位置特有的部分。

## 一、范围

每部作品在云端只有一条记录，写着最近看到哪一章（集）的哪个位置。`BCA-SYNC-009` 允许这种精简记录、禁止原样的历史行。

| 内容 | 是否同步 | 说明 |
| --- | --- | --- |
| 漫画 | 是 | 每部漫画一条：最近读的那一章与页码。其余章节的「已读」标记不同步 |
| 视频 | 是 | 每部作品一条：线路、第几集、看到第几秒、总时长 |
| 站点书 | 是 | 每本书一条：最近读的章节与阅读位置 |
| 临时资源历史 | 否 | 不属于任何来源 |
| 本地导入的书、书签 | 否 | 书文件本身不在 iCloud |

不上云的字段：会过期的播放地址、播放请求配置、播放状态、本机图片缓存键、规则快照、上一章与下一章地址。
对端设备拿到记录后，这些由它自己按规则重新取。

## 二、云端记录

记录类型 `HistoryEntry`，放在 `BrowseCraftSync` 区域，21 个字段，都不建索引。记录名由「类型 + 来源 + 作品标识」做哈希得到。
字段部署到 Production 后只能增不能删。

| 字段 | 类型 | 漫画 | 视频 | 站点书 |
| --- | --- | --- | --- | --- |
| `schemaVersion` | Int64 | 版本号 | 同 | 同 |
| `kind` | String | `comic` | `video` | `book` |
| `sourceID` | String | 来源 | 同 | 同 |
| `workKey` | String | 漫画条目 ID | 作品键 | 详情地址 |
| `itemID` | String | — | 作品编号 | 条目 ID |
| `title` | String | 漫画名 | 片名 | 书名 |
| `coverURL` | String | 封面 | 同 | 同 |
| `detailURL` | String | — | 详情页 | 详情页 |
| `unitKey` | String | 章节键 | 剧集键 | — |
| `unitTitle` | String | 章节名 | 集名 | 章节名 |
| `unitURL` | String | 章节地址 | 播放页地址 | 章节地址 |
| `pageIndex` | Int64 | 看到第几页 | — | — |
| `sourceIndex` | Int64 | — | 线路序号 | — |
| `episodeIndex` | Int64 | — | 集序号 | — |
| `playbackTime` | Double | — | 看到第几秒 | — |
| `duration` | Double | — | 总时长 | — |
| `locatorJSON` | String | — | — | 阅读位置 |
| `totalProgression` | Double | — | — | 全书进度 |
| `visitedAt` | Date/Time | 最近一次看的时间 | 同 | 同 |
| `updatedAt` | Date/Time | 合并时比较用 | 同 | 同 |
| `deletedAt` | Date/Time | 删除标记 | 同 | 同 |

上传前经过安全门禁（`BCA-SYNC-008`）：大小预算、地址里不得带用户名密码、阅读位置必须是合法 JSON。

## 三、同步规则

- **本机改动怎么发现**：三张历史表的写入方不登记同步。每轮同步在下载合并之前，拿历史表与本机账本 `history_sync_ledger` 对比：
  账本里没有的作品是新增；行时间晚于账本时间是改动；账本里还活着而历史表里没有了是删除；账本记着已删除而历史表里又有了是恢复
  （恢复用当前时间盖过删除标记）。对比出的作品登记进待上传队列。
- **什么时候同步**：跟着现有的全部触发时机，另加一条——App 退到后台时同步一次，并向系统要一小段后台时间等它跑完。
  刚看到哪里要在放下这台设备时就传上去，另一台设备打开时才接得上。
- **合并**：比较「更新时间与删除时间中较晚的那个」，晚的赢；相同时删除标记优先。整条记录一起换，不逐字段合并。
- **下载后写入本机**：按 `kind` 写进对应的历史表，没上云的字段留空。漫画写成那一章的历史行，不动这部漫画本机已有的其他章节行，
  页码变了时清掉本机留着的上一页地址与缓存键；视频同一集只更新进度与时间、保留本机已解析的播放地址，换了集则换行；
  书同时写历史行与阅读位置。云端版本赢了的作品，本机为它排着的上传作废。
- **来源不在本机**：记录指向的来源在本机不存在（也不是内置来源）时不写入，云端记录保持不动；本机这类历史也不上传。
  同一轮同步里来源先于历史下载。
- **删除一条历史**：其他设备收到删除标记后删掉这部作品的历史；书的阅读位置不随历史删除，与本机删除历史一致。
- **删除来源**：本机连带删除该来源的历史（`BCA-DB-004`）后，下一轮对比会把这些作品登记为删除并上传删除标记，
  云端不留孤儿记录；撤销删除后历史回来，按恢复处理。
- **类型不认识或版本更新的记录**逐条跳过，不拖垮整批。
- **区域被删后重建**：清空账本，下一轮把本机现有历史当作新增重新登记上传。

## 四、本机改动

- **数据库**：迁移追加一张 `history_sync_ledger`（用户、类型、来源、作品标识、改动时间、删除时间）。三张历史表不改结构；
  待上传队列与同步状态表沿用现有的，增加一种实体类型。
- **同步代码**：`HistoryEntryCloudPayload` 与 `HistoryEntryIdentity`；`HistoryEntrySyncService`（下载合并、上传待传项）；
  `GRDBHistoryEntrySyncLocalStore`（对比账本、历史表与续看记录互转）；`CloudKitRecordMapper` 与 `CKSyncEngineCloudRecordStore` 增加第三种记录；
  `CloudSyncCoordinator` 在来源、收藏之后加历史这一步。三种记录共用一次区域拉取。
- **界面**：云同步页「同步的内容」第三行显示「历史与阅读进度 · N 部」，N 是本机有历史且来源还在的作品数；
  状态卡与首次开启窗口的说明把「看到哪里」算进同步内容。「上次同步」的上传与下载数包含历史。

## 五、环境与部署

iCloud 用哪个环境只由安装包的签名方式决定，与工程里的环境名无关。

| 怎么装到设备上 | 工程配置 | iCloud 环境 |
| --- | --- | --- |
| Xcode 运行到模拟器或真机 | Debug 或 Release | Development |
| 归档 → TestFlight 或 App Store | TestFlight 或 Release | Production |

两个环境的数据完全隔开。工程里没有任何地方指定 iCloud 环境，权限文件只声明容器。

云端字段有改动时，发 TestFlight 或商店包之前必须先在 CloudKit 控制台执行「Deploy Schema Changes」把 Development 的 schema 部署到 Production；
Production 不允许应用自己新建字段，漏了这一步，带新字段的记录会上传失败。

## 六、实现位置

- `BrowseCraft/Domain/Models/Sync/HistoryEntryCloudPayload.swift`
- `BrowseCraft/Application/Ports/Sync/HistoryEntrySyncLocalStore.swift`、`BrowseCraft/Application/Sync/HistoryEntrySyncService.swift`
- `BrowseCraft/Infrastructure/Database/Sync/GRDBHistoryEntrySyncLocalStore.swift`、
  `BrowseCraft/Infrastructure/Database/Records/Sync/HistorySyncLedgerRecord.swift`、迁移 `v8.history-sync-ledger`
- `BrowseCraft/Infrastructure/CloudKit/Sync/CloudKitRecordMapper.swift`、`CKSyncEngineCloudRecordStore.swift`
- `BrowseCraft/Application/Sync/CloudSyncCoordinator.swift`、`CloudSyncPayloadSecurityValidator.swift`
- `BrowseCraft/App/AppContainer.swift`（退到后台时同步）、`BrowseCraft/BrowseCraftApp.swift`
- `BrowseCraft/Features/Settings/CloudSync/`（第三行与文案）
