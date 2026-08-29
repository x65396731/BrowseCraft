# 运行期广告过滤承接规则匹配结果（设计）

更新时间：2026-08-29  
状态：设计待评审，**App 代码未修改**  
影响源：全部 Video 源（触发场景来自 `jable-tv`）  
问题类型：广告过滤职责在生成器与 App 之间重复且划分不清

## 一、结论

后端生成器将**停止**把运行期广告策略编译进规则 regex。规则今后只声明
「从哪里取媒体地址」，不再携带广告排除的负向前瞻。相应地，
**App 需要对规则匹配到的结果执行广告过滤**。

后端侧的合同改动已在规则仓库完成（`BC-PLAYBACK-049`，并修订
`BC-PLAYBACK-021`/`022`）。本文是 App 侧的对应设计，**本轮未修改任何 App 代码**。

## 二、为什么改

后端原先要求 `media`/`iframe`/`script` 三类 runtime regex 必须带证据型负向前瞻，
而前瞻内容只有两个来源：采集期**实际失败**的 host，与 AI 决策里被排除的 route。

这把一个安全属性绑到了偶然事件上：

- `kpkuang.org` 能生成规则，是因为它有注册墙，未登录访问被导向 `/user/reg.html`，
  构成一次实际失败，于是有了排除项；
- `jable.tv` 生成失败，是因为它**干净**——没有注册墙、采集全程无失败、
  AI 也没排除任何 route，排除集为空，编译直接抛错。

同一个站今天失败、明天不失败，得到的规则就不同。而且四种 loading 变体里，
`WEBUI_PAGE` 完全不受该要求约束，另外三种受约束，没有统一理由。

## 三、App 侧现状（只读核对，未改动）

需要的机制**已经存在，并且已在播放时生效**：

- `BrowseCraft/Application/Runtime/Common/Filtering/SourceContentNoiseFilter.swift`
  - `SourceContentNoiseContext` 含 `playbackCandidate`
  - `SourceContentNoiseReason` 含 `advertising`、`popupOrOverlay`、`tracking`、
    `externalPromotion`
- `BrowseCraft/Features/Library/Video/Player/VideoWebPlayerCoordinator.swift:108`
  `shouldBlockLikelyNoiseNavigation(_:)` 在播放时对**主框架导航**调用该过滤器，
  `action == .discard` 即拦截。
- 词表 `SourceDetectionLexicon`：`advertising` 12 条、`tracking` 9 条、
  `externalPromotion` 7 条、`popupOrOverlay` 5 条，另有 `zh-Hans` 分表，
  经 `SourceDetectionLexicon.load(bundle:)` 从 App Bundle 读取。

## 四、需要新增的部分

现有过滤作用于**导航 URL**。规则匹配结果是另一条路径，需要补上：

| 输入 | 说明 |
| --- | --- |
| 规则 `media.url` 抽取得到的候选 URL | 含从页面正文 regex 提取的 `.m3u8` |
| 规则 `iframe.url` 抽取得到的候选 URL | |
| 该候选的上下文 | 至少包含所属 source、规则 id、抽取所用 selector |

| 输出 | 说明 |
| --- | --- |
| `keep` / `discard` / `deprioritize` | 复用 `SourceContentNoiseDecision` |

`discard` 的候选不得进入播放；若全部候选被 discard，按既有 `fallback` 语义处理，
不得静默播放被判为广告的地址。

## 五、必须一并决定的两件事

1. **词表更新节奏**。规则是数据、可服务端更新；词表现在随 App Bundle 发布，
   遇到新广告形态需要发版。原先改规则即可。
   **建议单独立项讨论词表下发**，但它不应阻塞本设计。
2. **召回率由 App 侧证明**。后端从此不再能证明「该 regex 运行时不会匹配到广告」。
   这一缺口在后端合同里已如实写明（`BC-PLAYBACK-049`），
   补上它的唯一途径是 App 侧的判定用例。

## 六、验收

- App 侧：对已知广告 `.m3u8` 与正常 `.m3u8` 各一组的判定用例；
  以及「全部候选被 discard 时按 fallback 处理」的用例。
- 后端侧：取消排除要求后 `jable.tv` 与 `kpkuang.org` 复跑，
  分别报告 `normalizationStatus` 与 `runtimeValidationStatus`。
- **App 未完成前**，后端即使生成成功，`runtimeValidationStatus` 也只能是
  `candidate-only`；规则仓库的 `APP-MEMO-008` 保持 `not-started` 直到 App 代码
  实际完成并通过上述用例。

## 七、边界

- 本文不改变候选级广告 assessment 的职责——那仍在生成期，由后端负责。
- 本文不涉及 App 自身的广告投放模块（`BrowseCraft/Shared/Ads/`），二者无关。
- 未修改 BrowseCraft 或 BrowseCraftCore 的任何代码。
