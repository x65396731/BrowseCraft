# jable.tv M3U8 播放规则问题交接

更新时间：2026-08-21  
状态：根因已确认，待更新 Catalog 规则并完成 App 端回归  
影响源：`jable-tv`  
问题类型：Video V2 播放页直接媒体抽取失败后进入 WebUI fallback

## 一、交接结论

当前问题不需要优先修改 App 播放器代码，应先修正 jable.tv 的
`playbackRules[].media.url` 抽取规则。

播放页的内联脚本中存在 `hlsUrl = "...m3u8"`，但当前规则使用
`function: "text"` 读取 `<script>`。BrowseCraftCore 的 HTML `text` 最终调用
SwiftSoup `Element.text()`；`<script>` 内容属于 DataNode，不会作为 TextNode 返回，
因此 m3u8 正则没有获得可匹配的输入。

直接媒体和 iframe 候选都为空后，规则声明的 `fallback: "webUI"` 按合同把结果
转换为 `mediaKind=iframePlayer`、`status=pageOnly`。UI 随后打开原播放网页，行为与
当前 App 代码一致。

## 二、现象与日志证据

样例播放页：

```text
https://jable.tv/videos/dldss-552/
```

App 已成功取得真实播放页 HTML：

```text
event=content-loaded antiBot=false bytes=95388 needsWebView=false
purpose=video requestScope=page url=https://jable.tv/videos/dldss-552/
```

随后播放结果为：

```text
event=debug message=[BrowseCraftVideoDetail] openEpisode playback-result
source=jable-tv episodeKey=dldss-552-1-1
mediaKind=iframePlayer status=pageOnly
```

紧接着打开网页播放器：

```text
event=debug message=[BrowseCraftVideoWebPlayer] appear/load
url=jable.tv/videos/dldss-552
```

这三组日志表明：

1. 播放页网络加载成功，不是该次请求被 Cloudflare 拦截。
2. Runtime 没有产出 `.m3u8`/`.mp4` 直接媒体候选。
3. Runtime 按规则进入 WebUI fallback。
4. Firebase、WEBP 解码、RBS/WebKit assertion 等警告发生在网页播放器打开之后，
   不是触发网页回退的原因。

原始日志：

```text
/Users/xiefei/.codex/attachments/5b4a8812-cc25-4bca-aa5c-b56c3e1eb5a2/pasted-text.txt
```

## 三、网页证据

应用内浏览器检查确认：

- 播放页存在多个 `script:not([src])`。
- 其中一个内联脚本声明 `var hlsUrl = "https://…/*.m3u8"`。
- 页面渲染后 `video#player.src` 是 `blob:`，不能直接把渲染后的 `src` 交给原生播放器。
- m3u8 URL 带临时签名/期限，必须每次从当前播放页重新解析，不能固化。

脱敏后的捕获证据：

```text
/Users/xiefei/Desktop/数据分析/jable.tv/20260820-videos-dldss-552/
/Users/xiefei/Desktop/核心规则/jable.tv-videos-dldss-552-核心规则.md
```

捕获文件已把完整临时签名替换为占位符，不包含个人 Cookie、Authorization 或完整媒体
token。

直接 HTTP 对照请求使用相同 iPhone User-Agent、但没有浏览器凭证时，返回 Cloudflare
`Just a moment...`。这说明后续回归必须继续关注 App 的凭证/Cookie 路径，但它不是本次
日志中的直接失败点，因为 App 当时已经取得 `95388` bytes 的真实页面。

## 四、规则根因

当前规则片段：

```json
"media": {
  "url": {
    "function": "text",
    "selectorKind": "css",
    "selector": "script:not([src])",
    "regex": "(?i)(https?://[^?&#=\\s]+(?:/[^?&#=\\s]*)*\\.m3u8(?:\\?[^#\\s]*)?)"
  },
  "kind": "hls"
}
```

相关实现链路：

```text
DefaultRuleExtractionEngine.apply(.text)
→ DefaultRuleExtractionEngine.text(from:)
→ SwiftSoupHTMLDocumentParser.text(of:)
→ Element.text()
```

关键代码位置：

- `../BrowseCraftCore/Sources/BrowseCraftCore/Parsing/Extraction/DefaultRuleExtractionEngine.swift`
- `../BrowseCraftCore/Sources/BrowseCraftCore/Parsing/Document/HTML/SwiftSoupHTMLDocumentParser.swift`
- `BrowseCraft/Application/Runtime/Video/Loading/VideoSourcePlaybackLoader.swift`
- `BrowseCraft/Features/Library/Video/Player/VideoPlayerViewModel.swift`
- `BrowseCraft/Features/Library/Video/Player/VideoWebPlayerView.swift`

`function: "raw"` 会读取选中节点的 `outerHTML`，其中包含 script DataNode，适合当前页面的
内联脚本媒体抽取。项目现有 Video playback parser 示例也使用 `raw + regex` 从 script 中
提取播放地址。

## 五、建议规则修改

### 最小修复

把播放媒体规则中的：

```json
"function": "text"
```

改为：

```json
"function": "raw"
```

现有宽泛 m3u8 正则已在当前页面的 script `outerHTML` 上确认可以命中；因此只改
`text → raw` 是最小修复。

### 推荐修复

建议同时把正则收窄到 `hlsUrl` 变量：

```json
"media": {
  "url": {
    "function": "raw",
    "selectorKind": "css",
    "selector": "script:not([src])",
    "regex": "(?i)\\bhlsUrl\\s*=\\s*['\"](https?://[^'\"\\s]+\\.m3u8(?:\\?[^'\"\\s]*)?)['\"]"
  },
  "kind": "hls"
},
"fallback": "webUI"
```

该片段只是待合入完整 Catalog 的候选修改，不应脱离完整 payload 单独提交。发布前必须对
最终序列化的 Catalog 执行当前仓库的严格 VideoSiteRule 校验和引用完整性检查。

## 六、iframe 规则处理建议

当前 iframe 规则同样使用 `function: "text"` 读取 script，并使用：

```text
^(https?://[^\s]+)$
```

即便改成 `raw`，完整 script/`<script>` 也不会满足“整个字符串就是 URL”的锚定条件。
此外，该页面存在广告 iframe，使用宽泛 `iframe[src]` 容易把广告地址误判成播放器。

建议：

- 删除当前无效的 `iframe` 规则。
- 保留显式 `fallback: "webUI"`，用于页面结构变化、媒体抽取失败或临时签名不可用时降级。
- 只有发现稳定、专用、已验证的播放器 iframe selector 时，再新增 iframe 分支。

## 七、Catalog 版本不一致

本次 App 日志与粘贴规则不是完全相同的 Catalog 版本：

| 对比项 | App 日志 | 粘贴规则 |
|---|---|---|
| 标签数量 | 5 | 4 |
| 首个 page id | `page-98128e73be10` | `page-cb2e3ac46904` |
| 首个 list rule id | `list-4aee6b4dbe7a` | `list-4aee6b4dbe7a` |

因此修改规则后必须同时确认：

1. 后台保存的是修改后的完整 Catalog。
2. App 已重新获取 Catalog，而不是使用旧缓存/旧快照。
3. App 日志中的 page id、标签数量和目标 Catalog 一致。
4. 实际加载的 playback rule id 是本次修改的规则。

粘贴规则：

```text
/Users/xiefei/.codex/attachments/bc55fea1-aca7-40fa-a3fc-2ad22292392f/pasted-text.txt
```

## 八、回归步骤与验收标准

本交接只完成诊断，没有执行以下回归。接手者更新完整 Catalog 后应验证：

1. 用 App 重新加载目标 Catalog，确认版本/id 与后台一致。
2. 打开一个 jable.tv 列表页，确认列表和封面仍正常。
3. 进入样例详情页，确认 episode/play page URL 正常。
4. 点击播放，确认 playback parser 产出一个 HLS 媒体候选。
5. 日志应出现等价结果：

   ```text
   mediaKind=m3u8 status=playable
   ```

6. UI 应进入原生播放器，不应出现：

   ```text
   [BrowseCraftVideoWebPlayer] appear/load
   ```

7. 验证 AVPlayer 对 m3u8 manifest 和分片的请求是否需要 `Referer`、Cookie 或其他公开请求头。
8. 验证临时签名过期后，重新点击播放会从最新页面取得新 URL，而不是复用旧媒体地址。
9. 验证媒体抽取失败时仍能按 `fallback: "webUI"` 打开网页，避免完全不可播放。

验收结果应分别记录：

- Catalog 严格校验状态。
- 播放页 HTML 请求状态和字节数。
- direct media candidate 数量。
- `mediaKind` 和 `status`。
- 原生播放器是否起播。
- manifest/分片是否存在 401、403 或签名过期。

## 九、是否需要修改 App 代码

当前证据不支持修改 App 播放器：

- App 已成功加载播放页。
- Runtime 正确遵循“直接媒体 → iframe → WebUI fallback”的顺序。
- `pageOnly` 正确路由到网页播放器。
- 根因位于站点规则用错误的提取函数读取 script。

只有出现以下新证据时，才考虑 App/Core 代码修改：

- 完整 Catalog 已更新并确认 App 加载的是新版本，但 `raw + regex` 在运行时仍无法产出候选。
- 候选已产出为 `.m3u8/.playable`，但播放请求无法携带规则已声明的必要请求头或 Cookie。
- 多个站点都需要 script DataNode 专用提取语义，而现有 `raw` 合同无法稳定表达。
- 规则生成器反复把 script 抽取错误生成为 `function: "text"`；此时应修正规则生成器，
  不是为 `jable-tv` 在通用播放器中增加 `sourceID` 特判。

禁止在通用执行器中增加 `jable-tv` 特判。

## 十、当前完成状态

- 已读取并比对用户提供的 App 日志和 Catalog。
- 已检查 BrowseCraft App/Core 播放链路代码。
- 已通过应用内浏览器确认播放页内联 `hlsUrl` 结构。
- 已确认当前正则在 script `outerHTML` 上可命中。
- 已保存脱敏网页证据和核心规则摘要。
- 未修改 App/Core 源码。
- 未修改后台 Catalog。
- 未运行测试或 build。
- 原生 HLS 起播、请求头/Cookie 和签名续期仍待规则更新后验证。
