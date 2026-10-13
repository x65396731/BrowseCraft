# 规则执行语义

App 与 Core 如何执行一条**已经下发的**规则。规则的生成、正规化与 catalog 发布合同不在本仓库，
定义点全部在 fwq 仓库 `docs/rules/`（`BCA-UI-003`：App 不创建也不编辑规则）。

影响范围：`BrowseCraftCore` 的 JSON 解析与规则模型、`BrowseCraftRuntime` 的各 kind runtime、
App 的网络载体。这些条款约束的是「拿到 JSON 之后怎么解释」，不约束怎么发请求。

> 实施与验证状态见 [STATUS.md](../STATUS.md)。

## 一、`responsePolicy` 的职责与边界

- `BCA-PARSE-001` API 业务响应状态必须通过规则的轻量 `responsePolicy` 表达：新规则显式选择 `transportOnly` 或
  `envelope`，业务状态路径、成功值、失败路径和消息路径都来自源站真实响应；未声明策略只进入隔离的 legacy 回退，
  禁止在通用执行器里新增 `0`、`200` 或 `sourceID` 特判。规则必须按真实响应显式声明该字段，见 `BC-CATALOG-008`。
- `BCA-PARSE-002` `responsePolicy` 是纯 JSON 业务语义合同，只回答「当前 JSON 是否允许继续解析」。它不得拥有或依赖
  HTTP 状态、Headers、最终 URL、请求发送、重试、取消、WebView、DOM 解析或 API/DOM 回退职责，也不得推动新增
  API 专用网络载体。
- `BCA-PARSE-003` `transportOnly` 只跳过 JSON 业务 envelope 判断，不代表接管或改变网络行为。itemPath 必须区分
  `missing/null/typeMismatch/empty/nonEmpty`；真实空数组是解析结果，非空原始项映射后全空属于合同错误。
- `BCA-PARSE-004` 显式 `responsePolicy` 永不进入 legacy；缺少 `responsePolicy` 时才允许执行隔离的旧规则兼容判断。

## 二、凭据与账号语义

- `BCA-PARSE-005` 不存在 `credentialStoreOrAnonymous` 字段。匿名/公共回退使用 context 的 `value`、`anonymousValue`
  或 `default`；登录值只放在 `userValue`，并使用受支持的 `{credentialStore.*}` 引用。
- `BCA-PARSE-006` `ReaderImageAPIRule.emptyResultPolicy="requiresAccount"` 只能用于已验证的成功响应中原始 `itemPath`
  数组确实为空的账号权限语义，不能根据 selectorEmpty、标题、错误字符串或最终映射空结果猜测登录需求。
  第二条允许路径（定义点 fwq `BC-COMIC-147`，本层只引用）：规则显式声明了 `requiresAccount`，且章节页最终地址
  缺少规则模板引用的 `{chapter.finalURL.*}` token——这是规则作者的显式声明加一个确定性事实，不是猜测；
  落点 `ComicSourceReaderLoader`。

## 三、执行边界

- `BCA-RUNTIME-001` API 规则执行边界固定为：沿用既有网络加载 → 沿用既有 JSON 解析 → 显式 `responsePolicy` 或
  legacy 二选一 → itemPath → 字段映射。网络层继续独立处理通用 HTTP/传输行为，规则语义层不得复制或改写网络策略。
- `BCA-RUNTIME-005` 页面取页分流器（`DefaultPageLoader.loadContent`）在规则未声明 `needsWebView`、直接请求却收到
  挑战页（`RuleExecutionError.antiBot`）时，用同一 `PageLoadRequest` 改走 WebView 通道再取一次；其它错误（网络、状态码）照旧抛出，
  不把 WebView 变成万能兜底。依据：规则的「不需渲染」由引擎在**服务器出口**按影子取回判定（fwq `BC-COMIC-159`），而执行跑在**手机出口**，
  两者对 Cloudflare 的处境不同（2026-10-06 toonily：章节页家用出口 403 `cf-mitigated: challenge`、服务器出口 200），引擎观察不到手机出口，
  这一层只能在 App 处理；WebView 通道已有挑战页状态机（`BC-EVIDENCE-081`，`WKWebViewChallengeInterstitialGate`）。无反爬的站不会进入回退，取值逐字不变。
  对应 fwq `APP-MEMO-026`。实现 `BrowseCraft/Infrastructure/Network/DefaultPageLoader.swift`；用例 `PageContentLoaderTests`（挑战页回退、其它错误不回退）。
  **Cookie 回写**：WebView 通道判定拿到真文档（挑战状态机 `.document`）时，把 `WKHTTPCookieStore` 里对该页主机生效的 Cookie
  （域名等于主机或主机是其子域）写回 `HTTPCookieStorage.shared`——封面 / 图片请求（`SharedHTTPCookieHeaderProvider`）与之后的直接请求才带得上过挑战得到的放行 Cookie；
  放行 Cookie 绑定 UA，两条路都用规则 `sharedRequest` 的 UA。每次 WebView 成功都回写，不以「本次看到挑战页」为条件。
  回写只用公开属性重建 Cookie（名 / 值 / 域 / 路径 / Secure / HttpOnly / 过期 / SameSite，`WebViewCookieSync.unpartitioned`）——带分区等私有属性的 Cookie，
  `HTTPCookieStorage.cookies(for:)` 按网址取不回；回写日志带 `readBack` 当场核对。实现 `BrowseCraft/Infrastructure/Network/WebViewCookieSync.swift`、`WKWebViewHTMLLoader.swift`；用例 `WebViewCookieSyncTests`。
  **书类封面的请求配置**：`ResolveLibrarySourcePresentationUseCase.imageRequestConfig` 对 book 规则按与 `BookSourceRuntime` 取列表同一继承
  （`sharedRequest` → 页 `request` → 列表规则 `request`）给出请求配置，书架 / 收藏 / 历史封面与作品页封面（`BookSiteDetailViewModel.coverRequestConfig`）同用；
  `cookiePolicy` 为空时 `CookieHeaderResolver` 只带规则写死的 Cookie、一条系统 Cookie 都不带，所以配置不能为空。真机证实与排查过程见 [status-log.md](../history/status-log.md)。
- `BCA-RUNTIME-006` 列表分页的页码代入统一为 `startPage + N − 1`（N 为 1 起的页序号；`PaginationRule.startPage` 缺省 1，book 的 `BookListPagination.startPage` 同义）：
  三 kind 的代入点（影视 `VideoRulePaginationResolver`、漫画 `ComicSourceListLoader` → `URLResolvingService.listURL(page:)`、书 `BookSourceRuntime.listURL`）都经它换算，
  不带该键的规则行为逐字不变。依据 fwq `BC-LIST-124`：0 起页码站（rouman5、3kor）第 1 页在地址里写 0，引擎交付 `startPage: 0`。
  **门控**：旧版 App 解码时忽略 `startPage`、把 N 原样代入会静默错一页，所以目录请求带 `features=startPage` 声明能力（`LoadCatalogSourcesUseCase.requestedFeatures`，与 `kinds` 同一机制），
  服务端把需要未声明能力的来源过滤掉；新增规则能力时在同一处登记。对应 fwq `APP-MEMO-027`。
  实现 `BrowseCraftCore/.../SiteRuleModels.swift`（`PaginationRule.startPage` / `sitePageNumber(forPage:)`）、`VideoSiteRuleValidationOperations` 放行键、`ComicSiteRuleV2ValidationOperations` 拒负数；用例 `PaginationStartPageTests`。
- `BCA-RUNTIME-007` 直接请求通道（`AlamofireHTTPClient.loadContent`）的状态码判定与 App 预检同口径（fwq `BC-PREFLIGHT-062` / `063`；引擎采集同样把非 2xx 当失败）：
  最终响应状态码在 200..<400 内照旧交给规则解析；400 及以上时先判挑战页——是挑战页仍抛 `antiBot`，由 `BCA-RUNTIME-005` 回退 WebView；
  不是挑战页抛 `RuleExecutionError.httpStatus(url:statusCode:)`，**拒绝页的正文不再交给规则解析**。
  依据：2026-09-29 xjortho 拦桌面 UA 返回 403，正文被当成列表页解析，用户看到「规则解析出错」、以为规则坏了（fwq `MEMO-App-请求被拒显示成规则解析出错`）；
  失败必须按成因说清楚，站点拒绝与规则出错是两种成因。
  **用户文案**按状态码分四类、都带状态码：404 / 410「找不到这个页面」，429「限制了访问频率」，5xx「暂时无法访问」，其余 4xx（含 401 / 403 / 451）「拒绝了这次访问」；
  诊断类别记 `network`，不记 `parse`（与 `antiBot` 同类：都是站点没给出可解析的页面）。分类与文案只在 `RuleExecutionErrorClassifier` 一处。
  **范围**：只管 HTML 直接请求。`loadData`（API / XML 原始字节）不在内——接口的业务失败由 `responsePolicy` 判（`BCA-PARSE-001`），401 这类在那里可能映射成登录提示，
  网络层先拦会盖掉更具体的说明；WebView 通道（`needsWebView` 与挑战页回退）拿不到状态码，仍按解析结果报错。
  **已知边界**：搜索无结果时以 404 回应的站，用户看到的会从「没有结果」变为「找不到这个页面」；到 2026-10-10 无实例，出现时再按搜索场景单独处理。
  实现 `BrowseCraft/Infrastructure/Network/AlamofireHTTPClient.swift`（`contentFailure(statusCode:html:url:)`）、`BrowseCraftDomain/.../RuleExecutionError.swift`；
  用例 `AlamofireHTTPClientTests`（状态码与挑战页判定）、`PageContentLoaderTests`（状态码错误不回退 WebView）、`RuleExecutionErrorClassifierTests`（四类文案与诊断类别）。
- `BCA-RUNTIME-008` 搜索第 1 页按规则解析出 0 条、而这次取页**发生过跳转**（落地地址与请求地址不同）时，把落地地址当作品页，
  按用户点开作品时的同一条路径（书：`pageID` 为空时取第一个列表页的作品页规则；漫画：`primaryDetailEntry`）加载一次；
  取到非空标题**且**至少 1 个章节，就把它作为唯一一条结果返回（`detailURL` = 落地地址，标题 / 封面取作品页的），否则照旧（书返回空列表，漫画抛 `selectorEmpty`）。
  兜底那次加载的任何错误都不外抛，按原结果报。第 2 页起、有结果、没跳转都不进兜底，取值逐字不变。
  依据：fwq `BC-SEARCH-022` ⑤ 已知边界——关键词恰为某部作品全名时，站点从搜索直接跳进作品页（piaotia「龙藏」），按结果列表解析为空，用户看到「没有结果」。
  量面（fwq `scripts/measure_search_fullname_redirect.py`，零网络，1,091 份搜索核实报告 / 129 主机）：首查用全名直跳作品页的 5 主机全部交付了搜索——
  sto55、piaotia、uukanshu、23qb（书）、mangakatana（漫画）；影视 0 例，本条不覆盖影视，出现实例再加。结果页靠 meta refresh / 脚本跳到作品页的 0 例。
  **判据只用「跳转 + 作品页规则取得到标题和章节」**，不认站、不认地址形状；站点把空结果跳回首页 / 搜索页时作品页规则取不到章节，落回原结果。
  代价：只在「0 条 + 跳转」时多一次取页。书在已取回的落地文档上直接解析，只有作品页规则要一跳目录（`chapterListURL` / `chapterFragmentURL`）时才多取；
  漫画按作品页取页链路重取一次落地地址（POST 搜索站的落地页是可直接 GET 的作品页）。对应 fwq `APP-MEMO-032`。
  实现 `BrowseCraftRuntime/.../Book/BookSourceRuntime.swift`（`search` → `redirectedDetailItem`）、`.../Comic/ComicSourceRuntime.swift`（`search` → `redirectedDetailItem`）与
  `.../Comic/Loading/ComicSourceSearchLoader.swift`（`SearchSourceResult.redirectedLandingURL`）；用例 BrowseCraftRuntime 包 `SearchRedirectLandingRuntimeTests`（书：直跳成一条且不重取落地页、落地无章节不兜底、没跳转不进兜底、跳转判定只忽略片段与末尾斜杠）；漫画一路无固定输入（归档只 mangakatana 1 例）。
- `BCA-RUNTIME-009` 书类目录自身分页（fwq `BC-BOOK-061` / `APP-MEMO-033`）：详情规则带 `chapterPagination` 时，`urlTemplate` 是**相对引用**，
  以 `chapterRule` 所应用的那份文档（作品页；有 `chapterListURL` 时是目录页）的最终地址为基址解析；第 1 页就是已取回的文档、不重取，
  第 N 页写 `startPage + N − 1`（`BCA-RUNTIME-006` 同一换算）。从第 2 页起逐页取（同一请求配置，referer 为上一页），同一 `chapterRule` 解析、按阅读地址去重追加；
  **这一页没有新章节、取页或解析失败、达到 `maxPages` 即停**，已取到的章节保留、不整体报错。`maxPages` 不超过 `BookSiteRuleValidator.maxChapterPaginationPages = 100`（用户 2026-10-11 定）。
  只在 DOM 章节、非片段目录（`chapterFragmentURL`）分支生效；搜索直跳兜底（`BCA-RUNTIME-008`）只确认落地页有章节，不翻目录页。不带该键时逐字不变；旧版 App 忽略该键、只列第一页（与此前相同，不门控）。
  Core 校验：`urlTemplate` 必须含占位符且是相对引用（不以 `/` 开头、不带协议），只与 `chapterRule` 搭配、不与 `chapterAPI` / `chapterFragmentURL` 同现。
  依据：fwq 量面 3 主机目录自身分页（笔趣阁 `index_{page}.html` 每页约 100 章、oop.tw `?p={page}` 每页 30 章、ffppt），此前目录截在第一页却报成功（读书需求文档需求五后半）。
  实现 `BrowseCraftCore/.../BookSiteRuleModels.swift`（`BookDetailRule.chapterPagination`）、`BookSiteRuleValidationOperations.swift`；`BrowseCraftRuntime/.../Book/BookSourceRuntime.swift`（`appendingChapterPages`）；
  用例 BrowseCraftRuntime 包 `BookChapterPaginationRuntimeTests`（逐页到无新章节、中途失败保留、`maxPages` 与 0 起页码、不带键只取一页、Core 校验）。
- `BCA-RUNTIME-010` 规则在取到的页面上**匹配不到内容**时，同一运行时操作换手机 Safari UA（`ClientUserAgent.mobileSafari`）重做**一次**（fwq `APP-MEMO-037`，设计稿第 54 节；
  用户 2026-10-13「App 端兜底或许可行，因为规则只会在手机端使用」→「所有来源都开，App 单端改」）。
  触发只认「匹配不到内容」：`RuleExecutionErrorClassifier` 归为 `selectorEmpty` 的错误，或调用方声明的空结果（列表第 1 页 0 条、书类目录 0 章）；
  网络、状态码、挑战未过、规则配置等错误不触发，搜索 0 条不算（可能就是没搜到）——不把换 UA 变成万能兜底（同 `BCA-RUNTIME-005`）。
  重做成功即按来源记「用手机 UA」（`UserDefaults`，键为来源 id，版本取 `Source.updatedAt`，规则更新后重新判），之后该来源的取页一律带手机 UA；
  重做仍匹配不到则照旧抛原错误、记「手机 UA 也不行」不再重试。UA 在两条取页路径的组头处统一套用（`AlamofireHTTPClient.urlRequest` 规则头与上下文头之后、
  `WKWebViewHTMLLoader.urlRequest` 组头时，后者经 `customUserAgent` 生效）；重做期间同一来源的其它取页也带手机 UA。
  依据：站点按 UA 分桌面 / 手机两套模板（seyouxiaoshuo 同一分类页桌面 UA `common-list` 0、iPhone UA 16）；困难档云端 `/scrape` 官方文档不能指定 UA，
  挑战站被升到实体机浏览器、拿回手机模板（huanmengacg `common-list` 52），规则按手机模板写成，App 用规则桌面 UA 取到桌面模板 →「规则没有匹配到内容」。
  放行 Cookie 绑 UA（本文 `BCA-RUNTIME-005` 回写说明），换 UA 后遇挑战照旧走 WebView 挑战状态机，首次会慢一次。不改 App 预检、不改引擎交付 UA。**2026-10-13 修订（用户「要，图片跟随来源的身份」）**：封面 / 列表图跟随来源的 UA 选择——`ResolveLibrarySourcePresentationUseCase.imageRequestConfig` 在来源已判定用手机 UA 时把 `imageHeaders`（及 `imageRequest.headers`）的 `User-Agent` 换成手机 Safari；依据 huanmengacg 封面与页面同在 Cloudflare 后面（直接请求 403 `cf-mitigated: challenge`），放行 Cookie 绑过挑战时的 UA，图片换了身份就回挑战页。还没打开过来源（未过挑战、没有放行 Cookie）时的预览封面仍取不到，不在本条内。
  实现 `BrowseCraft/Application/UseCases/Source/SourceUserAgentFallback.swift`（调用点：列表刷新、搜索、漫画详情、阅读章节、书类详情与正文、影视详情与播放）、
  `BrowseCraftDomain/.../ClientUserAgent.swift`（`mobileSafari`）；用例 `SourceUserAgentFallbackTests`（重做并记住、其它错误不触发、重做仍空报原错误且不再重试、空结果触发、规则更新重判、只换 UA、封面跟随来源 UA）。
- 直接请求通道跟随重定向时，跳转目标是 `http://` 的一律升成 `https://` 再跟（`AlamofireHTTPClient.httpsUpgradingRedirector`，`HTTPSUpgrade.upgraded`），HTML 取页与 `loadData` 原始字节请求同一个重定向器；不开全局 ATS 例外。
  引用点：fwq `BC-BOOK-050`（sfacg 作品页 302 到 http 的移动站再 301 回 https，URLSession 在 http 那一跳被 ATS 拒，而规则生成引擎的客户端无 ATS 跟得过去）；与有声书 mp3 地址的处置同一纪律。
  本来就是 https 或不是 http(s) 的地址原样跟随。
同域的另外三条不在本文：kind 分流纪律 `BCA-RUNTIME-002` 与目录解码兼容硬约束 `BCA-RUNTIME-004`
在 [Book-Kind-Wiring-Design.md](Book-Kind-Wiring-Design.md)，播放候选过滤 `BCA-RUNTIME-003` 在
[RuntimeAdFilter-Design.md](RuntimeAdFilter-Design.md)。
