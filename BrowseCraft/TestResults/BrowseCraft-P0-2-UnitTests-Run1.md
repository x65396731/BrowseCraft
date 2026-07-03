# BrowseCraft P0-2 Unit Test Result

Date: 2026-07-03 13:36 JST

## Command

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination id=E94D17BA-093C-4BFF-9AE5-BA586156CDB5 \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P0-2-UnitTests-Run1.xcresult \
  test
```

## Result

- Status: passed
- Target: BrowseCraftTests
- Test count: 8
- Failure count: 0
- Result bundle: `BrowseCraft/TestResults/BrowseCraft-P0-2-UnitTests-Run1.xcresult`

## P0-2 Assertions Added

### urlPatternsDecodeLegacyStringShape

Purpose: prove legacy `URLPatterns` string fields still decode after adding structured URL templates.

Assertions:

- `series == "https://example.test/comics/{idCode:}"`
- `list == "https://example.test/list/{page}"`
- `detail == "https://example.test/detail/{idCode:}"`
- `gallery == "https://example.test/chapter/{cidCode:}"`
- `search == "https://example.test/search?q={keyword:}"`
- `seriesTemplate == nil`
- `listTemplate == nil`
- `detailTemplate == nil`
- `galleryTemplate == nil`
- `searchTemplate == nil`

### urlPatternsDecodeStructuredTemplateShape

Purpose: prove structured templates can express page, keyword, and URL-derived placeholders.

Assertions:

- `listTemplate.template == "https://example.test/list/{page:1:20}"`
- `searchTemplate.template == "https://example.test/search?q={keyword:}&from={urlQuery:from}"`
- page placeholder:
  - `kind == .page`
  - `start == 1`
  - `step == 20`
- search placeholders:
  - first placeholder `kind == .keyword`
  - first placeholder `encoding == .urlQueryAllowed`
  - second placeholder `kind == .urlQuery`
  - second placeholder `name == "from"`
  - second placeholder `defaultValue == "home"`

## Existing Regression Coverage

- `builtInListRuleParsesComicCards`: passed
- `builtInReaderRuleParsesChapterPages`: passed
- `builtInDetailRuleParsesOnlyScopedChapters`: passed
- `builtInDetailRuleDoesNotFallbackToGlobalChapterLinks`: passed
- `extractRuleDecodesLegacySingleFunctionShape`: passed
- `extractRuleDecodesSelectorKindAndFunctionChainShape`: passed

## Notes

- P0-2 only adds URL template model shape and decode coverage.
- Existing URL execution behavior remains unchanged; `URLResolvingService` still uses the legacy `{page}` replacement path.
- `.xcresult` is ignored by `.gitignore`; this Markdown file is the human-readable record.
