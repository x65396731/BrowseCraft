# 读书 kind 接入 Readium 交接单

更新时间：2026-09-13
状态：依赖接入完成（未 build、未提交）；功能对接等服务器接口完成后再开始
影响范围：BrowseCraftCore 的 SwiftSoup 依赖、BrowseCraft 工程依赖图；漫画线与影视线代码零改动

## 一、交接结论

1. 读书 SDK 选定 Readium Swift Toolkit 3.11.0（`readium/swift-toolkit`，BSD-3）。它同时覆盖
   EPUB / PDF / 有声书三种 Navigator，书签与续读位置统一用 `Locator` 表达，是 iOS 上唯一
   仍在维护且满足这三项要求的开源 SDK。备选 FolioReaderKit 已于 2020 年归档；BookPlayer
   是 GPL 的 App 不是 SDK，只能当交互参考。
2. Readium 要求 SwiftSoup ≥ 2.13.5，而上游 2.13.5 直到 master（2026-09-13）都带着一个会黏连
   中文列表字段的 `text()` bug。项目改为锁定自家 fork，并用 Xcode 本地包覆盖化解与 Readium
   的同标识冲突。这一层已闭合，有闸门测试和预构建检查把关。
3. 功能层（Domain 的 book kind、Application 用例、Features 阅读器 UI）一行未写。等服务器
   接口定稿后按第五节的顺序推进。

## 二、已落地的改动

### 已提交

| 仓库 | 提交 | 内容 |
|---|---|---|
| BrowseCraftCore | 732211d | SwiftSoup 从 2.11.3 切到 fork `x65396731/SwiftSoup@18fbffd`，按 commit 锁定；新增 inline 空白闸门测试 |
| BrowseCraft | 39f2241b | 同步 Package.resolved，移除旧版 SwiftSoup 带来的 LRUCache、swift-atomics 传递依赖 |

### 未提交（工作树）

- `project.yml`：新增 Readium 3.11.0（exactVersion）；App 目标链接 ReadiumShared、
  ReadiumStreamer、ReadiumNavigator、ReadiumAdapterGCDWebServer；新增 `../SwiftSoup`
  本地覆盖包；新增预构建阶段「Check SwiftSoup Override」。
- `scripts/check-swiftsoup-override.sh`（新文件）：校验本地覆盖包存在、工作树干净、HEAD 等于
  Core 锁定的 commit；失败时打印修复命令。
- `BrowseCraft.xcodeproj/.../Package.resolved`：Readium 及 7 个传递依赖入锁；swiftsoup 条目
  因改为本地包而消失，属预期。
- `docs/architecture.md` 第 3、8 节、`scripts/README.md`、`AGENTS.md`：机制说明。
- 工程已用 `scripts/regenerate-project.sh` 重新生成，`xcodebuild -resolvePackageDependencies`
  通过：SwiftSoup 解析为本地路径，无冲突。

本机另有一份 fork 克隆在 `/Users/xiefei/Desktop/SwiftSoup`（与 BrowseCraftCore 平级），
分支 `browsecraft/text-whitespace-fix`，HEAD 18fbffd。换机器时按 `scripts/README.md`
里的命令重新克隆。

## 三、SwiftSoup fork 的来龙去脉

### bug 是什么

`Element.text()` 应把 inline 元素之间的换行缩进归一化成一个空格。2.13.5 起
`StringUtil.appendNormalisedWhitespaceBytes` 在「当前文本不含空白」的三处提前返回里没有把
`lastWasWhite` 复位。纯 ASCII 文本走另一条快速路径会正确复位，非 ASCII 文本不会，于是
「中文词 + 换行 + 下一个词」时换行被当作重复空格丢掉。

```html
<div><a>冒险</a>
<a>2024</a>
<a>热血</a>
<a>搞笑</a></div>
```

| 版本 | `text()` |
|---|---|
| 2.11.3 | 冒险 2024 热血 搞笑 |
| 2.13.5 – master | 冒险 2024 热血搞笑 |

### 证据

- 172 份真实语料（`BrowseCraftTests/Resources/PreflightFixtures`）逐文件比对 2.11.3 与 2.13.9
  的 `body().text()`：171 份不同，全部是空白差异。
- 打上三行修复后重跑：差异只剩 `&nbsp;` 归一化为普通空格和尾部空格裁剪，这两项是 2.13 有意
  对齐 jsoup 的改动；漫画解析层本来就把 `\u{00a0}` 替换成空格，不受影响。
- 项目自身语料测量用例（发布模式）：2.11.3 为 42 秒，2.13.9 为 104 秒，fork 为 44 秒。
  2.13.9 的额外耗时来自「首次属性 / class / id 选择器为整份文档建索引」，上游 master 已修，
  fork 基于 master 所以一并拿到。

### 机制

- BrowseCraftCore 按 commit 锁定 fork（`swift test` 走这条），同 KSPlayer 的做法。
- Readium 依赖官方 `scinfu/SwiftSoup`，SPM 不允许同标识两个 URL。`project.yml` 把
  `../SwiftSoup` 加为本地包，Xcode 用本地包覆盖整张依赖图里的同标识远程引用，Readium 也被
  指到 fork。
- 两条路必须同一 commit，`scripts/check-swiftsoup-override.sh` 作为预构建阶段把关。
- 闸门：`RuleExtractionEngineTests.testHTMLAdapterTextKeepsSeparatorBetweenInlineElementsAfterNonASCIIText`。
  2.11.3 与 fork 通过，2.13.5 – 2.13.9 失败。任何 SwiftSoup 升级或切回官方都先看它。
- 不向上游开 PR（用户决定）。上游哪天修了，切回官方 URL、删本地覆盖包、删脚本与预构建阶段即可。

## 四、验证命令

```bash
cd ../BrowseCraftCore && swift test
```

预期 218 条通过、4 条跳过（需要 `PREFLIGHT_FIXTURES_DIR` 的测量用例）、0 失败。

```bash
scripts/check-swiftsoup-override.sh
```

```bash
xcodebuild -resolvePackageDependencies -project BrowseCraft.xcodeproj -scheme BrowseCraft
```

整包 build 已于 2026-09-13 深夜通过一次（`xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft`，模拟器 iPhone 16 Pro，Debug，0 error）：
Readium 与 KSPlayer、Firebase 在同一目标里链接没有符号或资源冲突。影视线与漫画线的真机复核（第五节第 5 条）仍待用户。

## 五、服务器接口就绪后的推进顺序

1. **先定内容来源。** 两条路 Domain 建模差别大：
   - 本地文件（用户导入 EPUB / PDF / M4B）：Readium 直接打开，最快跑通 Locator 书签和 UI。
   - 站点抓取（与漫画线同构）：按规则抓章节文本 / 音频地址，包装成 Readium Web Publication
     manifest（RWPM）喂给 Navigator；有声书用 manifest 里的远程音频 href。
   建议先做本地文件把阅读器与书签闭合，再接抓取。服务器接口返回的字段直接决定 manifest
   怎么拼，所以接口定稿前不要动 Domain。
2. **新增 `book` kind** 时按现有 comic / video / rss 的分流模式扩展 `CatalogSource.Kind` 与
   `SourceConfiguration`，不得在通用执行器里加 kind 特判（AGENTS.md 与既有惯例）。
3. **Navigator 接线**：EPUBNavigatorViewController、PDFNavigatorViewController、AudioNavigator
   （无 UI，需自建播放器界面）。CBZ 分支不接，漫画线保持自研阅读器。
4. **书签模型**：`navigator.currentLocation` 序列化为 JSON 落库即书签，`initialLocation` 恢复
   进度，`locations.totalProgression` 做进度条。与漫画、视频现有进度模型互不干扰。
5. **首次 build 后**再做真机复核：影视线与漫画线各过一遍，确认 Readium 链接进来后没有波及。

## 六、风险与待办

- Readium 的 develop 分支要求 Swift 6.2 与 Xcode 26.4，4.0 处于 alpha。只跟 3.x tag。
- 本地覆盖包不入库，新环境必须先克隆，否则 `xcodebuild` 解析失败；预构建脚本会给出命令。
- fork 基于上游 master 未发布提交（2026-09-12 合入的一批性能与选择器修复），规则测试与 172 份
  语料已过，但尚未真机复核影视线与漫画线。首次 build 后补这一步。
- 工作树里的第二阶段改动未提交，由用户决定何时提交。
