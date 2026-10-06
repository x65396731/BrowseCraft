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

## 三、执行边界

- `BCA-RUNTIME-001` API 规则执行边界固定为：沿用既有网络加载 → 沿用既有 JSON 解析 → 显式 `responsePolicy` 或
  legacy 二选一 → itemPath → 字段映射。网络层继续独立处理通用 HTTP/传输行为，规则语义层不得复制或改写网络策略。
- `BCA-RUNTIME-005` 页面取页分流器（`DefaultPageLoader.loadContent`）在规则未声明 `needsWebView`、直接请求却收到
  挑战页（`RuleExecutionError.antiBot`）时，用同一 `PageLoadRequest` 改走 WebView 通道再取一次；其它错误（网络、状态码）照旧抛出，
  不把 WebView 变成万能兜底。依据：规则的「不需渲染」由引擎在**服务器出口**按影子取回判定（fwq `BC-COMIC-159`），而执行跑在**手机出口**，
  两者对 Cloudflare 的处境不同（2026-10-06 toonily：章节页家用出口 403 `cf-mitigated: challenge`、服务器出口 200），引擎观察不到手机出口，
  这一层只能在 App 处理；WebView 通道已有挑战页状态机（`BC-EVIDENCE-081`，`WKWebViewChallengeInterstitialGate`）。无反爬的站不会进入回退，取值逐字不变。
  对应 fwq `APP-MEMO-026`。实现 `BrowseCraft/Infrastructure/Network/DefaultPageLoader.swift`；用例 `PageContentLoaderTests`（挑战页回退、其它错误不回退）。
- `BCA-RUNTIME-006` 列表分页的页码代入统一为 `startPage + N − 1`（N 为 1 起的页序号；`PaginationRule.startPage` 缺省 1，book 的 `BookListPagination.startPage` 同义）：
  三 kind 的代入点（影视 `VideoRulePaginationResolver`、漫画 `ComicSourceListLoader` → `URLResolvingService.listURL(page:)`、书 `BookSourceRuntime.listURL`）都经它换算，
  不带该键的规则行为逐字不变。依据 fwq `BC-LIST-124`：0 起页码站（rouman5、3kor）第 1 页在地址里写 0，引擎交付 `startPage: 0`。
  **门控**：旧版 App 解码时忽略 `startPage`、把 N 原样代入会静默错一页，所以目录请求带 `features=startPage` 声明能力（`LoadCatalogSourcesUseCase.requestedFeatures`，与 `kinds` 同一机制），
  服务端把需要未声明能力的来源过滤掉；新增规则能力时在同一处登记。对应 fwq `APP-MEMO-027`。
  实现 `BrowseCraftCore/.../SiteRuleModels.swift`（`PaginationRule.startPage` / `sitePageNumber(forPage:)`）、`VideoSiteRuleValidationOperations` 放行键、`ComicSiteRuleV2ValidationOperations` 拒负数；用例 `PaginationStartPageTests`。
同域的另外三条不在本文：kind 分流纪律 `BCA-RUNTIME-002` 与目录解码兼容硬约束 `BCA-RUNTIME-004`
在 [Book-Kind-Wiring-Design.md](Book-Kind-Wiring-Design.md)，播放候选过滤 `BCA-RUNTIME-003` 在
[RuntimeAdFilter-Design.md](RuntimeAdFilter-Design.md)。
