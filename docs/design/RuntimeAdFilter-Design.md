# 运行期广告过滤承接规则匹配结果（设计）

更新时间：2026-08-29  
状态：**已实施并验证**——`BrowseCraftTests` 全目标通过
（Swift Testing 353 项 / 58 suites + XCTest 27 项，0 失败），含本设计新增的 9 项判定用例  
影响源：全部 Video 源（触发场景来自 `jable-tv`）  
问题类型：广告过滤职责在生成器与 App 之间重复且划分不清

## 一、结论

后端生成器将**停止**把运行期广告策略编译进规则 regex。规则今后只声明
「从哪里取媒体地址」，不再携带广告排除的负向前瞻。相应地，
**App 需要对规则匹配到的结果执行广告过滤**。

后端侧的合同改动已在规则仓库完成（`BC-PLAYBACK-049`，并修订
`BC-PLAYBACK-021`/`022`）。App 侧的合同随后补齐为
`APP-MEMO-008` 段的 `BC-EVIDENCE-071`–`BC-EVIDENCE-075`
（规则仓库 `docs/rules/video-runtime-acceptance.md`），
实施决定的完整论证见规则仓库
`docs/history/2026-08-29-app-runtime-noise-filter-implementation-design.md`。

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

## 四之二、实施时被测量推翻的两条默认假设

写代码前先用仓库里已落盘的 **1381 条真实 media URL** 复算了一遍判定，得到两条
本文第三节没有覆盖的事实。两条都改变了实施方式。

### F1：按字面复用过滤器，对媒体候选完全惰性

`SourceContentNoiseFilter` 对广告类理由设有豁免：候选看起来属于播放结构就不判广告。
`.playbackCandidate` 形态下该豁免只看 `url.path`，判据词表 `playbackStructure`
里就有 `m3u8`、`mp4`——**规则匹配到的媒体候选，其 path 必然含这两者**，
于是豁免恒成立。实测 1381 条中丢弃 **0** 条；
`https://adserver.example.test/vast/preroll-ad.m3u8` 判 keep。

修法（`BC-EVIDENCE-071`）：候选携带一个已声明事实
（`SourceContentPlaybackAssurance.inferred` / `.ruleDeclared`）区分「播放身份是猜的」
与「播放身份是规则声明的」，后者不取得该豁免。既有调用方不传该字段，行为逐字不变。

### F2：原始 query 子串匹配在签名 token 上产生假阳性

关掉豁免后 1381 条中丢弃 4 条：2 条是真广告（`s1.kwai.net/bs2/ad-i18n-dsp/…`），
2 条是假阳性——签名 token `…QAD-55w` 命中了 `ad-` 这个两字符标记。

修法（`BC-EVIDENCE-072`）：URL 参与词表子串匹配时只取 `scheme://host/path`。
query 的判别本来就由 `hasSuspiciousNavigationURLSignals` 的结构化计分承担，
原始子串匹配是重复的第二种解释。收窄后：真阳性 2 条不变，假阳性归零。

`source id`、规则 id 与 selector 只作为**审计上下文**记录，不进入词表匹配——
它们是规则自身的文字，不是候选的身份证据；否则同一个候选会因规则写法不同而得到不同裁决。

## 四之三、实际落点

| 位置 | 改动 |
| --- | --- |
| `Application/Runtime/Common/Filtering/SourceContentNoiseFilter.swift` | 新增 `SourceContentPlaybackAssurance`；`hasPlaybackSignal` 改为读该事实并删去一处两分支同值的死 `switch`；URL 证据收窄到 `scheme://host/path` |
| `Application/Runtime/Video/Loading/VideoSourcePlaybackLoader.swift` | 唯一过滤挂载点，位于 `validateParsedPlayback` 之后、任何路线判定之前；`VideoPlaybackNoiseAdmission` 承载准入结果与审计 |
| `Application/Runtime/Video/Playback/VideoPreparedPlaybackExecutionSession.swift` | 新增 route reason `allCandidatesFilteredAsNoise` |

`media → iframe → fallback` 决策树**一行未改**——它读到的候选集已是过滤后的集合。
route facts 仍只留内存，未触碰 evidence 导出 schema。

## 五、必须一并决定的两件事

1. **词表更新节奏**。规则是数据、可服务端更新；词表现在随 App Bundle 发布，
   遇到新广告形态需要发版。原先改规则即可。
   **建议单独立项讨论词表下发**，但它不应阻塞本设计。
2. **召回率由 App 侧证明**。后端从此不再能证明「该 regex 运行时不会匹配到广告」。
   这一缺口在后端合同里已如实写明（`BC-PLAYBACK-049`），
   补上它的唯一途径是 App 侧的判定用例。

## 六、验收

- App 侧：9 项用例（`SourceContentNoiseFilterTests` 4 项、
  `VideoSourcePlaybackLoaderTests` 5 项）**全部通过**，覆盖广告 host / `/ads/` 路径的 `.m3u8`
  被丢弃、带签名 query 的正常 `.m3u8` 保留、全部候选被 discard 时按 fallback 走页面播放且不播放
  被丢弃的地址、无 fallback 时带独立 reason 失败、广告 iframe 被丢弃、`deprioritize` 只改顺序。
  同一次运行里 `BrowseCraftTests` 全目标通过（Swift Testing 353 项 + XCTest 27 项），
  既有噪声过滤与播放 loader 用例无回归，改动文件零编译警告。

  `xcode-select` 指向 CommandLineTools，用环境变量覆盖即可，不需要 sudo：

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,id=C612B32B-9D17-4C9A-B82E-8036D535E59F' -derivedDataPath .derivedData -only-testing:BrowseCraftTests
  ```
- 后端侧：取消排除要求后 `jable.tv` 与 `kpkuang.org` 复跑，
  分别报告 `normalizationStatus` 与 `runtimeValidationStatus`。
- 上述用例已跑通，规则仓库的 `APP-MEMO-008` 现记实施 `implemented` /
  验证 `full-suite-passed`，**本项对发布的阻塞已解除**。发布本身仍需用户单独授权。
  `runtimeValidationStatus` 仍是 `candidate-only`，原因是 `BC-EVIDENCE-047` 规定的
  「没有独立 App runtime evidence 就不得声称 runtime-validated」，与广告过滤无关。

## 七、边界

- 本文不改变候选级广告 assessment 的职责——那仍在生成期，由后端负责。
- 本文不涉及 App 自身的广告投放模块（`BrowseCraft/Shared/Ads/`），二者无关。
- 未修改 BrowseCraftCore 的任何代码；BrowseCraft 侧只改上表三个文件与两个测试文件，
  未新增源码文件，因此不需要重新生成 XcodeGen 工程。
