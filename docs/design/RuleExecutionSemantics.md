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
同域的另外三条不在本文：kind 分流纪律 `BCA-RUNTIME-002` 与目录解码兼容硬约束 `BCA-RUNTIME-004`
在 [Book-Kind-Wiring-Design.md](Book-Kind-Wiring-Design.md)，播放候选过滤 `BCA-RUNTIME-003` 在
[RuntimeAdFilter-Design.md](RuntimeAdFilter-Design.md)。
