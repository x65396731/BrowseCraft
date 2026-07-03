# BrowseCraft P1-6.1 Built-in Source Coverage Matrix

中文注释：本文件用于整理当前内置源、规则包和 App 解析链路的测试覆盖情况，后续 P1-6 拆分任务以这里的缺口为准，避免重复做已经验证过的工作。

## 覆盖结论

| 内置源 / 能力 | 规则定义位置 | 现有覆盖 | 当前结论 | 后续建议 |
| --- | --- | --- | --- | --- |
| MYCOMIC 列表解析 | `BrowseCraftRulesKit/Sources/BrowseCraftRulesKit/BrowseCraftPrivateRuleCatalog.swift` | `SwiftSoupListParserTests.builtInListRuleParsesComicCards` + `BuiltInRuleHTMLFixtures.listHTML` | 已覆盖标题、详情 URL、封面、最新话文本，属于 App 解析器级回归 | 保持现状；真实站点 DOM 变化时再补站点研究记录 |
| MYCOMIC 详情章节解析 | 同上 | `SwiftSoupDetailParserTests.builtInDetailRuleParsesOnlyScopedChapters`、`builtInDetailRuleDoesNotFallbackToGlobalChapterLinks` | 已覆盖章节容器作用域，且明确防止全页面 `chapters` 链接误匹配 | 保持现状；如果规则迁到纯 V2 结构，再补 V2 fixture 对照 |
| MYCOMIC 阅读页图片解析 | 同上 | `SwiftSoupReaderParserTests.builtInReaderRuleParsesChapterPages` | 已覆盖正文图片、lazy-load `data-src` 优先、上下章、目录、标题面包屑 | 保持现状；回归测试继续用既存 MYCOMIC 页面即可 |
| MYCOMIC 分类 tab 合并 | App `SiteRule.availableListTabs` | `SiteRuleV2CompletenessTests.v2ListPagesMergeAdditionalLegacyListTabs` | 已覆盖 V2 pages 与 legacy `listTabs` 合并，不再只剩“发现” | 如果后续引入站点级 tabGroup，可扩展同一测试 |
| Pepper&Carrot 列表入口 | `BrowseCraftRulesKit/Sources/BrowseCraftRulesKit/BrowseCraftPrivateRuleCatalog.swift` + `/Users/trs/CodexMemory/site-research/peppercarrot.md` | site-research 记录了真实 URL 与 selector 结论；RulesKit 测试未覆盖 list selector | 规则结论已记录，但缺少可执行回归测试；目前主要依赖人工回归 | 建议 P1-6.2 补 RulesKit 列表 HTML fixture，覆盖 `a[href*="/cn/webcomic/ep"]:not(:has(img))` |
| Pepper&Carrot 一层列表直达阅读 | 同上 | 规则中 `treatDetailURLAsChapter = true`；App 有通用 Detail/Reader handoff 测试，但没有 Pepper 专用 fixture | 能力存在，真实源验证通过；自动覆盖不够精确 | 建议 P1-6.3 补一层源 fixture，确认列表 item 可直接进入 reader |
| Pepper&Carrot 阅读页图片解析 | 同上 | `BrowseCraftRulesKitTests.pepperCarrotReaderImageRuleMatchesEpisodePages` | 已覆盖 `/0_sources/`、`/low-res/`、`Pepper-and-Carrot_by-David-Revoy` 图片选择，并排除旧 `/webcomics/`、`/lang/` 误规则 | 保持 RulesKit 测试；若 App parser 支持 mainScope 后，再补 App 侧 reader fixture |
| RequestConfig / imageRequest / WebView / Cookie | App V2 模型与 Application 层 | P1-4 系列测试记录：`BrowseCraft-P1-4-Complete-UnitTests-Run1.md` | 已覆盖请求配置传递、图片请求 header、WebView 分流、Cookie 合并 | 真实站点需要特殊 header/cookie 时再补站点级 fixture |
| ListContext / sections / tabGroup | App V2 模型、解析器和用例 | P1-5 完整测试记录：`BrowseCraft-P1-5-Complete-UnitTests-Run1.md` | 已覆盖 ListContext 附加、PageRule.sections、Detail/Reader context scope、TabGroup 展开 | 作为后续 V2 复杂页面的基础能力，不需要 P1-6 重复实现 |
| RulesKit package 刷新 | `BrowseCraft/scripts/update-rules-package.sh` | 脚本、README、P1-6.4 审计记录 | 流程已固化为“确认远端 main SHA -> 更新两处 Package.resolved -> resolve -> pod install，不 build”；P1-6.4 已补 `--dry-run` / `--check` 只读检查模式 | 后续刷新前可先 dry-run/check；真实刷新仍需用户明确触发 |

## 现有证据文件

- 中文注释：MYCOMIC 的 App 解析器回归样例集中在 `BrowseCraft/BrowseCraftTests/Fixtures/BuiltInRuleHTMLFixtures.swift`，用于避免测试文件被大段 HTML 干扰。
- 中文注释：MYCOMIC list/detail/reader 的解析断言分别位于 `SwiftSoupListParserTests`、`SwiftSoupDetailParserTests`、`SwiftSoupReaderParserTests`。
- 中文注释：Pepper&Carrot 的真实 DOM 结论位于 `/Users/trs/CodexMemory/site-research/peppercarrot.md`，目前只同步了 Pepper&Carrot，没有其它站点研究文件。
- 中文注释：Pepper&Carrot 的 reader 图片 selector 回归位于 `BrowseCraftRulesKit/Tests/BrowseCraftRulesKitTests/BrowseCraftRulesKitTests.swift`。
- 中文注释：P1-4 与 P1-5 的完整测试结果分别记录在 `BrowseCraft/TestResults/BrowseCraft-P1-4-Complete-UnitTests-Run1.md` 和 `BrowseCraft/TestResults/BrowseCraft-P1-5-Complete-UnitTests-Run1.md`。

## P1-6 后续拆分建议

1. P1-6.2：补 Pepper&Carrot list selector 的 RulesKit fixture 测试，确认列表能取到 episode 标题和 `/cn/webcomic/ep...` 阅读页链接。
2. P1-6.3：补 Pepper&Carrot 一层源直达阅读的 App/RulesKit 边界测试，确认 `treatDetailURLAsChapter` 不会退回二层详情逻辑。
3. P1-6.4：已完成 package 刷新脚本可检查化；详见 `BrowseCraft/TestResults/BrowseCraft-P1-6-4-PackageRefreshScript-Audit.md`。

## 本轮未执行事项

- 中文注释：P1-6.1 是覆盖矩阵整理任务，本轮没有运行 `xcodebuild`、`swift test`、`pod install` 或 package 刷新。
- 中文注释：本轮没有修改 App 生产代码、RulesKit 规则代码或测试代码。
