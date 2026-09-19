# HANDOFF —— 会话入口

> 本文是**会话入口**，属 H 类（`BCA-DOC-011`）。它只承载四样东西：当前状态的现查口径、
> 未选候选与挂账的指针、环境与命令速查、归档索引。
>
> 它**不承载条款定义点，也不复述定义点正文**——判据全部在 C 类文档（入口 [`docs/README.md`](docs/README.md)），
> 瞬时状态全部在 [`docs/STATUS.md`](docs/STATUS.md)。
>
> 任何状态性数字（提交、推送、测试数、条款数、警告数）**在复述前必须现查，不得照抄本文**。
> 本文刻意不记这些数字，只记怎么查。
>
> **分工**：本文只记**纯 App 侧的工作**——分层与边界、构建与警告、Readium 与 book 接线、
> 资产与性能、文档架构。由规则生成引出的 App 改动（`APP-MEMO-*`）流水在 fwq 仓库的 `HANDOFF.md`，
> 这边只留指针，同一件事不写两份。

## 0. 当前状态（现查口径）

```bash
# 五仓 + SwiftSoup fork 的 HEAD、是否干净、是否有未推送
for d in BrowseCraft BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit SwiftSoup; do
  printf '%-22s ' "$d"
  git -C ~/Desktop/$d log --oneline -1
  printf '%-22s   未提交 %s 处，未推送 %s 个\n' '' \
    "$(git -C ~/Desktop/$d status --porcelain | wc -l | tr -d ' ')" \
    "$(git -C ~/Desktop/$d log --oneline @{u}.. 2>/dev/null | wc -l | tr -d ' ')"
done

# 文档闸门（改过 C 类文档 / STATUS / AGENTS 就跑，BCA-DOC-010）
python3 scripts/check-docs.py
```

各工作项的决策 / 设计 / 实施 / 验证状态见 [`docs/STATUS.md`](docs/STATUS.md)，一行一项，每格一个枚举值。
**`验证` 列的三级不可互相推断**：`full-suite-passed` 是离线测试全过，`simulator-passed` 是模拟器走通流程，
`device-passed` 是用户真机确认。模拟器通过不等于真机通过。

## 1. 未选候选与挂账（指针，不复述）

以下都在 `docs/STATUS.md` 里有行；挑活前按该文件第 0 节的三步核对，不要只看名字就开工。

**`required` 未完成：0 条。** 剩下的全是 `optional` 或已裁决不做。

- **等用户裁决**：fwq 的 `protectedResource` 与 `executionPolicy` 两条约束只有正文没有稳定 ID，
  本仓库只能按文档引用，是否请 fwq 分配 ID。
- **待核**：`scripts/update-rules-package.sh` 指向的 `BrowseCraftRulesKit` 不在当前五仓布局里，脚本是否已死。
- **无语料、等样本**：读书 kind 的四个接口变体（list / detail / reader 的 API 形态）。
- **已登记、无行动价值**：`BookBookmarksSheet` 是本地导入设计里未实现的计划名（入口已藏，该节是
  未建代码的设计留档）；F2-3 后半的显式 `ImagePrefetcher` 预取（`LazyVGrid` 本就提前实例化下一屏，
  收益未测到，暂缓）。
- **明确不做**（`rejected` / `superseded`，按名字跳过，不是待办）：本地书 B3 有声书播放器、PDF 与 CBZ、
  目录刷新时静默覆盖本地规则、jable.tv 播放根因（已由 fwq `BC-PLAYBACK-049` 承接）、
  CloudKit 门禁的字面量全面扫描（有意收窄，见 `BCA-SYNC-008`）、iOS 18.5 模拟器运行时、
  代码审计里四条被测量推翻的条目（F2-7、F2-10、F3-1、F3-2 与封面请求重复构造）。

## 2. 环境与命令速查

五个仓库是**同级 checkout 的 path 依赖**，没有版本 tag；App 的 `main` 只对得上兄弟仓的 `main`：

```
~/Desktop/
  BrowseCraft/            # App
  BrowseCraftCore/  BrowseCraftDomain/  BrowseCraftRuntime/  BrowseCraftAPIKit/
  SwiftSoup/              # 自家 fork，整张依赖图的本地覆盖（BCA-BUILD-002）
  fwq/                    # 规则生成引擎，BC-* 与 APP-MEMO-* 的定义点在这里
```

工具链要点：`xcodegen` 只保留 `/opt/homebrew` 下的 arm64 版（x86_64 那份已删，它在本机跑不了）；
Homebrew 从源码编译要求独立的 Command Line Tools 与 Xcode 同版本，只装 Xcode.app 不够。

```bash
# 工程文件不同步时先重新生成（BCA-BUILD-001）。project.yml 不引用任何文档路径，
# 所以纯文档改动不需要跑这条。
scripts/regenerate-project.sh

# 四个代码闸门 + 一个文档闸门。前两个也作为 pre-build 阶段跑。
scripts/check-architecture-boundaries.sh     # BCA-ARCH-001 ~ 005
scripts/check-swiftsoup-override.sh          # BCA-BUILD-002
scripts/check-ad-configuration.sh            # BCA-BUILD-003
scripts/check-bundled-image-assets.sh
python3 scripts/check-docs.py                # BCA-DOC-010

# build 与测试（AGENTS.md：只有用户明确要求时才跑）。destination 按「OS + 名字」指定：
# 不写 UDID（换机器就失效），也不能只写 name——裸 name 解析不到，必须带 OS。
# 运行时用 iOS 26 及以上：iOS 18.5 上测试包加载会缺 libswiftWebKit.dylib（Xcode 27 SDK
# 配旧运行时的错配），build 不受影响但跑不了测试。
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' build
xcodebuild -project BrowseCraft.xcodeproj -scheme BrowseCraft \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' test -only-testing:BrowseCraftTests

# 包各自的测试
for d in BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit; do
  (cd ~/Desktop/$d && swift test)
done
```

三个 scheme 的归档目标不同：`TEST BrowseCraft` 归档 `TestFlight` 配置（环境 TEST），
`BrowseCraft` 与 `PROD BrowseCraft` 归档 `Release` 作 PROD，后两者在广告单元还是 Google 示例值时拒绝构建
（`BCA-BUILD-003`）。`project.pbxproj` 是生成的且已 git-ignore，在 Xcode 的 Signing & Capabilities 里改的东西
会被下次 `regenerate-project.sh` 冲掉（`BCA-BUILD-004`）。

## 3. 归档索引

`docs/history/` 是只读归档（`BCA-DOC-009`）：不构成生产约束，不参与逐条核对，不得被引用为实施依据。
**归档里的「下一步」「待补」清单一律按当时的判断看待，不得照着开工**——先查 `docs/STATUS.md` 对应行。

| 归档 | 内容 |
| --- | --- |
| [status-log.md](docs/history/status-log.md) | 状态变更流水：被 `STATUS.md` 覆盖的旧值，与三分法从 C 类搬出的叙事事实 |
| [2026-09-19-docs-architecture-audit.md](docs/history/2026-09-19-docs-architecture-audit.md) | 文档架构审计与 D0–D5 迁移提案，含迁移前的量化基线 |
| [2026-09-18-code-audit.md](docs/history/2026-09-18-code-audit.md) | 五仓代码审计：警告清单、架构、性能热点与逐项修正纪事 |
| [Book-Kind-Wiring-batch-records.md](docs/history/Book-Kind-Wiring-batch-records.md) | 读书 kind 分批落地记录与模拟器 / 真机实测纪事 |
| [RSS-Removal.md](docs/history/RSS-Removal.md) | RSS 从五仓整体下线的执行记录与保留清单 |
| [Readium-Integration-Handoff.md](docs/history/Readium-Integration-Handoff.md) | Readium 选型与 SwiftSoup fork 的来龙去脉 |
| [JablePlaybackRule-Handoff.md](docs/history/JablePlaybackRule-Handoff.md) | jable.tv M3U8 抽取失败的根因交接 |
| [Phase0-Data-Contract-and-Security-Audit.md](docs/history/Phase0-Data-Contract-and-Security-Audit.md) | CloudKit 阶段 0 的数据合同与 payload 安全审计 |

当前有效的规范与设计在 [`docs/README.md`](docs/README.md) 第 6、7 节按任务列出。
