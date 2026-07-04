# BrowseCraft P3-9.7b RefreshSourceUseCase Boundary Audit - Run 1

Date: 2026-07-04

## Scope

- Audit `RefreshSourceUseCase` ownership and call sites.
- Decide whether P3-9.7c should only annotate, move implementation into Rule runtime, or migrate Sources UI to `RefreshSourceRuntimeUseCase`.
- Do not change Swift business code in this step.

## Current Call Sites

```text
AppContainer
  makeSourcesViewModel()
    creates RefreshSourceUseCase for SourcesViewModel

SourcesViewModel
  selectSourceAfterRefresh(_:)
    calls refreshSourceUseCase.execute(source:)
  refreshSource(_:)
    calls refreshSourceUseCase.execute(source:)

SourceRuntimeFactory
  makeRuleSourceRuntime(source:)
    creates RefreshSourceUseCase for RuleSourceRuntime

RuleSourceRuntime
  loadList(_:)
    calls refreshSourceUseCase.execute(source:listTab:page:)
```

## Boundary Findings

- `RefreshSourceUseCase` is still rule-only despite its generic name.
- It directly reads `source.rule.availableListTabs`, `source.rule.list`, and `source.rule.request(for:)`.
- It parses through `RuleParsingService.parseList(...)`.
- It writes parsed list items to `ContentRepository.replaceItems(...)`.
- `LibraryViewModel` already uses `RefreshSourceRuntimeUseCase`, so Library is not blocked by this legacy entry.
- `SourcesViewModel` still uses `RefreshSourceUseCase` directly for source selection refresh, manual refresh, and failed refresh retry.

## Option Assessment

### Path A: Keep In App UseCases With Stronger Comments

- Lowest risk.
- Does not improve physical ownership.
- Leaves the generic name in a shared App use case folder, which can mislead future RSS / Plugin work.

### Path B: Rule Runtime Internal Implementation + App Facade

- Recommended.
- Move the real implementation into `Application/Runtime/Rule/RuleSourceRefreshUseCase.swift`.
- Keep `Application/UseCases/RefreshSourceUseCase.swift` as an App facade for `SourcesViewModel`.
- Make `RuleSourceRuntime` depend on `RuleSourceRefreshUseCase` directly.
- This mirrors P3-9.5's pattern for reader execution: runtime internals are rule-prefixed, App feature callers keep stable App facades.
- Requires XcodeGen, pod install, and targeted tests because a Swift file is added/moved.

### Path C: Migrate SourcesViewModel To RefreshSourceRuntimeUseCase

- Most runtime-first.
- Too broad for P3-9.7.
- It changes Sources selection/refresh/retry behavior and may affect rule editing or built-in source flows.
- Better deferred to a dedicated Sources runtimeization node.

## Decision For P3-9.7c

Use Path B.

P3-9.7c should:

- Add `RuleSourceRefreshUseCase` under `Application/Runtime/Rule`.
- Move the current rule-backed refresh implementation there.
- Leave `RefreshSourceUseCase` in `Application/UseCases` as a thin facade for `SourcesViewModel`.
- Change `RuleSourceRuntime` and `SourceRuntimeFactory` to use `RuleSourceRefreshUseCase` directly.
- Keep behavior unchanged.

Do not migrate `SourcesViewModel` to `RefreshSourceRuntimeUseCase` in P3-9.7c.

## Static Checks

```sh
rg -n "RefreshSourceUseCase|refreshSourceUseCase|RefreshSourceRuntimeUseCase|refreshSourceRuntimeUseCase" BrowseCraft BrowseCraftTests
rg -n "source\\.rule|RuleResolver\\(\\)\\.resolve\\(source\\.rule\\)" BrowseCraft/Application/UseCases/RefreshSourceUseCase.swift BrowseCraft/Application/Runtime/Rule/RuleSourceRuntime.swift BrowseCraft/Application/Runtime/SourceRuntimeFactory.swift BrowseCraft/Features/Sources/SourcesViewModel.swift BrowseCraft/App/AppContainer.swift
find BrowseCraft/Application -maxdepth 3 -type d | sort
rg -n "Bridge|Adapter|unsupportedPersistedSourceKind" BrowseCraft BrowseCraftTests /Users/xiefei/Desktop/BrowseCraftCore/Sources /Users/xiefei/Desktop/BrowseCraftCore/Tests
git diff --check
```

## Static Check Result

- `RefreshSourceUseCase` direct callers are limited to `SourcesViewModel`, `RuleSourceRuntime`, `SourceRuntimeFactory`, App construction, and tests.
- Rule-only reads are inside `RefreshSourceUseCase` and `RuleSourceRuntime`.
- Application physical structure remains:

```text
BrowseCraft/Application
BrowseCraft/Application/Runtime
BrowseCraft/Application/Runtime/Debug
BrowseCraft/Application/Runtime/Rule
BrowseCraft/Application/UseCases
```

- `Bridge|Adapter|unsupportedPersistedSourceKind`: no matches.
- `git diff --check`: passed.

## XcodeGen / Pods / Tests

- No Swift files were modified in P3-9.7b.
- Did not run `./scripts/regenerate-project.sh`.
- Did not run `pod install`.
- Did not run xcodebuild tests.

## Next

- Next subsection: `P3-9.7c RefreshSourceUseCase boundary narrowing`.
- Plan update needed: no. P3-9.7c should proceed with Path B unless implementation reveals a larger hidden dependency.
