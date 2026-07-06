# BrowseCraft P5.1.4 VideoAdapterRegistry - Run 1

- 日期：2026-07-06
- 范围：视频 adapter 到 mapper 的执行分发层
- 类型：代码实现记录

## 完成内容

- 新增 `VideoAdapterRegistry`。
- 新增 `UnsupportedVideoHTMLMapper`。
- `SourceRuntimeFactory` 改为依赖 `VideoAdapterRegistry` 获取 video mapper。
- `VideoAdapter.macCMS` 和旧数据缺省 adapter 继续返回 `MacCMSVideoHTMLMapper`。
- `genericHTML`、`iframe`、`webView`、`plugin` 返回 `UnsupportedVideoHTMLMapper`。
- unsupported mapper 抛出明确错误：

```text
Video adapter <adapter> is not connected yet.
```

## 修改文件

```text
BrowseCraft/Application/Runtime/SourceRuntimeFactory.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterRegistry.swift
TestResults/BrowseCraft-P5-Video-Runtime-Strategy-Plan.md
```

## 验证

按用户项目习惯，本次没有运行测试，也没有 build。
