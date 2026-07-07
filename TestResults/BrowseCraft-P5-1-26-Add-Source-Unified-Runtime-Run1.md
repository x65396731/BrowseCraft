# BrowseCraft P5.1.26 Add Source Unified Runtime Run1

Date: 2026-07-08

## Scope

- Build the Add Source entry around the selected runtime instead of separate default pages.
- Keep comic, RSS, and video on the same visible add-source shell while allowing runtime-specific sections.
- Move comic/RSS/source-kit save timing to the same rule: save only after library/list load succeeds.
- Do not restore video source type auto-detection; video manual flow only logs facts until a valid manual rule exists.

## Implemented

- Added `PreviewRuntimeSourceUseCase` for the unified Add Source request step.
- Added `ValidateSourceListLoadUseCase` so source saves reject empty library/list output.
- Updated comic/RSS/catalog add use cases to validate runtime list output before saving to DB.
- Fixed comic/RSS add-source handoff by returning the successful `SourceListOutput` from add use cases and publishing a Library snapshot before selecting the new source.
- Added the unified `RuntimeSourceImportView` route from `AddSourceView`.
- Physically split source UI files by feature:
  - `Features/Sources/AddSource/`: add-source entry, runtime import shell, website rule import, package import, import sections.
  - `Features/Sources/Debug/`: runtime debug router, RSS debug, comic rule debug, video debug, shared debug result sections.
  - `Features/Sources/RuleSource/`: rule detail and rule JSON/basic-field editors.
  - `Features/Sources/Catalog/`: source catalog list.
- Added a unified Debug entry inside `RuntimeSourceImportView`.
- Added `SourceDebugRouterView` as the runtime debug dispatch layer.
- Kept comic-specific Rule JSON editing behind the comic runtime section.
- Added comic import debug through a temporary rule-backed `Source` and list rule debug summary.
- Kept RSS import on feed URL request plus list-load validation.
- Added RSS debug through feed request plus RSS/Atom parser preview logs.
- Changed RSS debug to keep request diagnostics even when XML parsing fails: URL, bytes, parser status/error, logs, and raw response preview are shown.
- Added editable URL input inside the runtime Debug sheet so users can adjust and rerun debug without leaving the debug view.
- Kept video import as URL inspection/logging only; it does not infer adapter or save a source.
- Added video debug through URL inspection preview logs only.
- Added Atom feed parsing support to `RSSFeedMapper` so feeds like `https://v2ex.com/index.xml` produce items instead of false empty results.

## Current Finding

`https://v2ex.com/index.xml` is an Atom feed:

- root: `<feed>`
- items: `<entry>`
- item link: `<link href="...">`
- dates: ISO-8601 `published` / `updated`

The previous RSS mapper only understood RSS 2.0 `<channel><item>`, so V2EX loaded successfully but mapped to `0` items.

## Pending

- Add a real Request Options editor for manual source import. This should pass through `RequestConfig` instead of showing placeholder controls.
- Decide which request fields are user-facing first: headers, referer, cookie policy, WebView requirement, or request method/body.
- Extend comic import debug from list-only summary to detail/reader handoff after the unified entry stabilizes.

## Tests

Not run. User instruction says not to run tests/build unless explicitly requested.
