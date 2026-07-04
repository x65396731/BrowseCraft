# BrowseCraft P3-7.9 Detail/Reader Runtime Handoff Assessment

- Date: 2026-07-04
- Scope: P3-7.9 Detail/Reader runtime handoff evaluation.
- Result: Assessment complete. No production code changes were made.

## Current Runtime Path

`RuleSourceRuntimeAdapter.loadDetail(_:)` and `loadReader(_:)` are already wired to the Core `SourceRuntime` contract, but they still adapt back into the existing App use cases:

```text
SourceDetailInput.detailURL
  -> synthetic ContentItem
  -> LoadChaptersUseCase.execute(source:item:)

SourceReaderInput.chapterURL
  -> synthetic ContentItem
  -> LoadReaderChapterUseCase.execute(source:item:chapterURLString:)
```

This keeps parsing, request selection, WebView/HTTP loading, rule resolution, and cache-independent Reader behavior inside the App layer.

## What Is Safe Today

- `SourceRuntimeContext.sourceID` is validated before Detail/Reader execution.
- `pageID`, `tabID`, `sectionID`, `sectionRole`, and `ruleID` are preserved through `ContentItem.listContext`.
- Detail parsing can still receive context and narrow by list section.
- Reader parsing can still receive context and narrow by list section.
- Direct-reader rules still work in the existing App path when the caller provides a real `ContentItem`.

## Gaps

- `SourceDetailInput` only carries `detailURL` and context. It cannot express the original item id, title, latest text, cover, or content type.
- `SourceReaderInput` only carries `chapterURL` and context. It cannot distinguish:
  - a selected chapter URL,
  - an item detail URL that should resolve chapters,
  - a catalog/detail URL,
  - a direct-reader URL.
- The synthetic `ContentItem` uses the URL as `id`, the source name as `title`, and `detailURL = chapterURL` for reader calls. This is acceptable as a temporary adapter behavior, but it is thinner than the main App Reader path.
- Direct-reader intent is currently inferred from `SiteRule.DetailRule.treatDetailURLAsChapter` plus `ContentItem.detailURL`. Core runtime input has no explicit portable intent field.
- Request override handling for Detail/Reader is not validated or implemented yet. The App use cases still select request config from the resolved rule.

## Recommendation

Do not replace the main Reader/Chapter UI path with runtime in P3-7.

Before Detail/Reader becomes a primary runtime-facing UI path, Core should grow an item handoff model or richer input fields, for example:

```text
SourceItemReference
  id
  title
  detailURL
  latestText
  contentType
  context

SourceDetailInput
  item: SourceItemReference

SourceReaderInput
  item: SourceItemReference?
  selectedChapterURL: URL?
  directReaderURL: URL?
  catalogURL: URL?
```

The exact shape can be finalized after P3-7.10 clarifies the runtime axis and before any Reader UI migration.

## Follow-Up Placement

- P3-7.10 should document that `SiteRule` is only the `RuleSourceRuntime` configuration format, while richer Detail/Reader handoff belongs to the runtime contract.
- P3-8 RSS runtime evaluation should reuse the same question: RSS items often already point to either detail pages or direct content.
- P3-9 plugin manifest planning should reserve a way for plugins to return item references and selected reader targets without pretending they are `SiteRule` fields.

## Verification

- No production code changed.
- No Swift files were added or moved, so XcodeGen was not run.
- No tests were run for this assessment-only node.
