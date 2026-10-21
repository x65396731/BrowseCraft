# 运行期广告过滤承接规则匹配结果

影响源：全部 Video 源（触发场景来自 `jable-tv`）  
问题类型：广告过滤职责在生成器与 App 之间重复且划分不清

> 实施与验证状态见 [STATUS.md](../STATUS.md)；验收过程与命令见 [status-log.md](../history/status-log.md)。

## 一、结论

后端生成器**不**把运行期广告策略编译进规则 regex。规则只声明
「从哪里取媒体地址」，不再携带广告排除的负向前瞻。相应地，
**App 需要对规则匹配到的结果执行广告过滤**。

后端侧的合同改动已在规则仓库完成（`BC-PLAYBACK-049`，并修订
`BC-PLAYBACK-021`/`022`）。App 侧的合同随后补齐为
`APP-MEMO-008` 段的 `BC-EVIDENCE-071`–`BC-EVIDENCE-075`
（规则仓库 `docs/rules/video-runtime-acceptance.md`），
实施决定的完整论证见规则仓库
`docs/history/2026-08-29-app-runtime-noise-filter-implementation-design.md`。

## 二、为什么改

成因在规则生成侧（负向前瞻把安全属性绑到采集期的偶然失败上），叙事见 [status-log.md](../history/status-log.md)；规则侧的现行合同以 fwq `BC-PLAYBACK-049` 为准，本文不复述。

## 三、既有的导航过滤

对**导航 URL** 的过滤在播放时生效：

- `BrowseCraftRuntime/Sources/BrowseCraftRuntime/Common/Filtering/SourceContentNoiseFilter.swift`
  - `SourceContentNoiseContext` 含 `playbackCandidate`
  - `SourceContentNoiseReason` 含 `advertising`、`popupOrOverlay`、`tracking`、
    `externalPromotion`
- `BrowseCraft/Features/Library/Video/Player/VideoWebPlayerCoordinator.swift` 的 `shouldBlockLikelyNoiseNavigation(_:)`
  在播放时对**主框架导航**调用该过滤器（调用点在 `VideoWebPlayerCoordinator+NavigationDelegate.swift`），
  `action == .discard` 即拦截。
- 词表 `SourceDetectionLexicon`：`advertising` 12 条、`tracking` 9 条、
  `externalPromotion` 7 条、`popupOrOverlay` 5 条（base 表），另有 en / ja / zh-Hans 分表；
  词表随 Runtime 包发布，经 `Bundle.module` 读取（`BCA-ARCH-006`）。

## 四、规则匹配结果的过滤

第三节的过滤作用于**导航 URL**。规则匹配结果是另一条路径，输入与输出如下：

| 输入 | 说明 |
| --- | --- |
| 规则 `media.url` 抽取得到的候选 URL | 含从页面正文 regex 提取的 `.m3u8` |
| 规则 `iframe.url` 抽取得到的候选 URL | |
| 该候选的上下文 | 至少包含所属 source、规则 id、抽取所用 selector |

| 输出 | 说明 |
| --- | --- |
| `keep` / `discard` / `deprioritize` | 复用 `SourceContentNoiseDecision` |

- `BCA-RUNTIME-003` `discard` 的候选不得进入播放；若全部候选被 discard，按既有 `fallback` 语义处理，
  不得静默播放被判为广告的地址。

## 四之二、两条判定细则

### 播放身份的豁免只给推断出来的候选

`SourceContentNoiseFilter` 对广告类理由设有豁免：候选看起来属于播放结构就不判广告。
`.playbackCandidate` 形态下该豁免只看 `url.path`，判据词表 `playbackStructure`
里就有 `m3u8`、`mp4`——**规则匹配到的媒体候选，其 path 必然含这两者**，
于是豁免恒成立。

判据的正文在 fwq `BC-EVIDENCE-071`，本文只留引用点（`BCA-DOC-001`）；App 侧的承载类型是 `SourceContentPlaybackAssurance`，落点见四之三。

### 词表匹配只看 `scheme://host/path`

判据的正文在 fwq `BC-EVIDENCE-072`，本文只留引用点（`BCA-DOC-001`）；落点见四之三。

## 四之三、落点

| 位置 | 职责 |
| --- | --- |
| `BrowseCraftRuntime/Sources/BrowseCraftRuntime/Common/Filtering/SourceContentNoiseFilter.swift` | `SourceContentPlaybackAssurance`；`hasPlaybackSignal` 读该事实；URL 证据只取 `scheme://host/path` |
| `BrowseCraftRuntime/Sources/BrowseCraftRuntime/Video/Loading/VideoSourcePlaybackLoader.swift` | 唯一过滤挂载点，位于 `validateParsedPlayback` 之后、任何路线判定之前；`VideoPlaybackNoiseAdmission` 承载准入结果与审计 |
| `BrowseCraftRuntime/Sources/BrowseCraftRuntime/Video/Playback/VideoPreparedPlaybackExecutionSession.swift` | route reason `allCandidatesFilteredAsNoise` |

`media → iframe → fallback` 决策树不感知过滤——它读到的候选集已是过滤后的集合。
route facts 只留内存，不进 evidence 导出 schema。

## 五、两条随之成立的边界

1. **词表更新节奏**。规则是数据、可服务端更新；词表随 Runtime 包发布（第三节），
   遇到新广告形态需要发版。是否改为服务端下发是独立的候选工作项（[STATUS.md](../STATUS.md) 的 optional 行），不属于本设计。
2. **召回率由 App 侧证明**。后端不证明「该 regex 运行时不会匹配到广告」，
   这一缺口在后端合同里写明（`BC-PLAYBACK-049`），由 App 侧的判定用例补上（第六节）。

## 六、验收覆盖面

- 覆盖广告 host / `/ads/` 路径的 `.m3u8`
  被丢弃、带签名 query 的正常 `.m3u8` 保留、全部候选被 discard 时按 fallback 走页面播放且不播放
  被丢弃的地址、无 fallback 时带独立 reason 失败、广告 iframe 被丢弃、`deprioritize` 只改顺序。
  用例在 `SourceContentNoiseFilterTests` 与 `VideoSourcePlaybackLoaderTests`。
- 发布由用户单独授权，不随本设计自动发生。
- `runtimeValidationStatus` 为 `candidate-only`，依据是 `BC-EVIDENCE-047` 规定的
  「没有独立 App runtime evidence 就不得声称 runtime-validated」，与广告过滤无关。

> 实施与验证状态见 [STATUS.md](../STATUS.md)；验收当次的用例数、全目标读数与所用命令见
> [status-log.md](../history/status-log.md)。

## 七、边界

- 本文不改变候选级广告 assessment 的职责——那仍在生成期，由后端负责。
- 本文不涉及 App 自身的广告投放模块（`BrowseCraft/Shared/Ads/`），二者无关。
