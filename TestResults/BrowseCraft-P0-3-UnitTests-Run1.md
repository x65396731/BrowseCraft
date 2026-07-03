# BrowseCraft P0-3 Unit Test Result

Date: 2026-07-03 13:39 JST

## Command

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination id=E94D17BA-093C-4BFF-9AE5-BA586156CDB5 \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P0-3-UnitTests-Run1.xcresult \
  test
```

## Result

- Status: passed
- Target: BrowseCraftTests
- Test count: 11
- Failure count: 0
- Result bundle: `BrowseCraft/TestResults/BrowseCraft-P0-3-UnitTests-Run1.xcresult`

## P0-3 Assertions Added

### listFieldsDecodeP03DisplayAndMediaFields

Purpose: prove list-card fields can express Yealico-style display/media metadata.

Assertions:

- `title.selector == ".title"`
- `cover.selector == "img.cover"`
- `largeImage.selector == "img.large"`
- `video.selector == "video source"`
- `detailURL.selector == "a.title"`
- `uploader.selector == ".uploader"`
- `datetime.selector == "time"`
- `datetime.param == "datetime"`

### detailFieldsDecodeP03SecondLevelPageFields

Purpose: prove detail fields can express total image count and second-level reader/album links.

Assertions:

- `title.selector == "h1"`
- `totalImages.selector == ".page-count"`
- `totalImages.regex == "(\\d+)"`
- `photoAlbumLink.selector == "a.album"`
- `secondLevelPageURL.selector == "a.reader"`

### chapterRuleDecodesCidCodeAliasForURLPlaceholder

Purpose: prove chapter rules can distinguish legacy `idCode` from chapter URL placeholder `cidCode`.

Assertions:

- `idCode.param == "data-id"`
- `cidCode.param == "data-cid"`
- `title.selector == "a.chapter"`
- `url.function == .url`

## Existing Regression Coverage

- `builtInListRuleParsesComicCards`: passed
- `builtInReaderRuleParsesChapterPages`: passed
- `builtInDetailRuleParsesOnlyScopedChapters`: passed
- `builtInDetailRuleDoesNotFallbackToGlobalChapterLinks`: passed
- `extractRuleDecodesLegacySingleFunctionShape`: passed
- `extractRuleDecodesSelectorKindAndFunctionChainShape`: passed
- `urlPatternsDecodeLegacyStringShape`: passed
- `urlPatternsDecodeStructuredTemplateShape`: passed

## Notes

- P0-3 only adds field model shape and decode coverage.
- Existing parser/runtime behavior remains unchanged.
- `.xcresult` is ignored by `.gitignore`; this Markdown file is the human-readable record.
