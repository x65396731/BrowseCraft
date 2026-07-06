# BrowseCraft P5.1.1 Runtime README - Run 1

- 日期：2026-07-06
- 范围：`BrowseCraft/Application/Runtime/README.md`
- 类型：文档更新

## 完成内容

- README 已按 `SourceDefinition + SourceRuntime` 作为架构主轴描述。
- 明确 `SiteRule` 只属于 `RuleSourceRuntime` 的配置格式。
- 明确 RSS、Video、Plugin 不继续扩展 `SiteRule`。
- 明确 `VideoSourceRuntime` 使用一层视频适配器分类：
  - `VideoAdapter.macCMS`
  - `VideoAdapter.genericHTML`
  - `VideoAdapter.iframe`
  - `VideoAdapter.webView`
  - `VideoAdapter.plugin`
- 明确 `MacCMSVideoHTMLMapper` 是 `adapter/macCMS` 下的内置 mapper，不是顶层 source kind。
- 明确复杂账号、验证码、签名、加密和私有流程进入 plugin runtime 规划。
- 移除 README 开头残留的 `P3-7` 阶段口径，改为阶段中性的 runtime 边界说明。

## 验收

```text
README 能解释 comic/rss/video/plugin 的 runtime 边界。
```

状态：通过文档检查。

## 验证

按用户项目习惯，本次没有运行测试，也没有 build。
