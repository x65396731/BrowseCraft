# BrowseCraft P5.1.2 VideoAdapterDetector - Run 1

- 日期：2026-07-06
- 范围：视频源适配器识别 MVP
- 类型：代码实现记录

## 完成内容

- 新增 `VideoAdapter`，并在 P5.1.3 迁移到 BrowseCraftCore：
  - `macCMS`
  - `genericHTML`
  - `iframe`
  - `webView`
  - `plugin`
- 新增 `VideoAdapterDetectionInput`：
  - `url`
  - `html`
  - `headers`
- 新增 `VideoAdapterDetection`：
  - `adapter`
  - `confidence`
  - `reasons`
  - `warnings`
- 新增 `VideoAdapterDetecting` 协议与 `VideoAdapterDetector` 默认实现。
- MVP 识别顺序：
  - MacCMS route / player marker
  - plugin-level restriction marker
  - iframe marker
  - WebView / JS shell marker
  - generic HTML video marker
  - unknown fallback to low-confidence `genericHTML`

## 修改文件

```text
BrowseCraft/Application/Runtime/Video/Mapping/VideoAdapterDetector.swift
BrowseCraftCore/Sources/BrowseCraftCore/Source/VideoSourceDefinitionModels.swift
BrowseCraft/Application/Runtime/Video/Mapping/VideoHTMLMapper.swift
TestResults/BrowseCraft-P5-Video-Runtime-Strategy-Plan.md
```

## 验证

按用户项目习惯，本次没有运行测试，也没有 build。
