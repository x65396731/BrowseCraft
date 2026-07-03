# BrowseCraft P0-4 Unit Test Result

Date: 2026-07-03 13:42 JST

## Command

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination id=E94D17BA-093C-4BFF-9AE5-BA586156CDB5 \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P0-4-UnitTests-Run1.xcresult \
  test
```

## Result

- Status: passed
- Target: BrowseCraftTests
- Test count: 14
- Failure count: 0
- Result bundle: `BrowseCraft/TestResults/BrowseCraft-P0-4-UnitTests-Run1.xcresult`

## P0-4 Assertions Added

### detailRuleDecodesP04SemanticNestedRules

Purpose: prove `tagRule` and `commentRule` decode as semantic nested rule structures.

Assertions:

- `tagRule.item.selector == ".tags a"`
- `tagRule.name.selector == "this"`
- `tagRule.url.function == .url`
- `commentRule.item.selector == ".comment"`
- `commentRule.avatar.selector == "img.avatar"`
- `commentRule.username.selector == ".user"`
- `commentRule.datetime.param == "datetime"`
- `commentRule.content.selector == ".content"`

### detailRuleDecodesP04VideoRuleShape

Purpose: prove structured `videoRule` can express item, url, thumbnail, link, and title.

Assertions:

- `videoRule.item.selector == "video, .video"`
- `videoRule.url.selector == "source"`
- `videoRule.url.param == "src"`
- `videoRule.thumbnail.param == "poster"`
- `videoRule.link.selector == "a.video-link"`
- `videoRule.title.selector == ".video-title"`

### videoRuleDecodesLegacyVideoURLShape

Purpose: prove old `videoUrl` remains decodable while the new structured fields stay optional.

Assertions:

- `videoUrl == "https://media.example/video.mp4"`
- `item == nil`
- `url == nil`

## Existing Regression Coverage

The same run also covered the existing parser and model decode tests:

- `sourceDecodeUsesDefaultTypeWhenTypeMissing`
- `parserKeepsCommonContainerWhenExtractingSiblingFields`
- `parserResolvesRelativeURLAgainstSourceBaseURL`
- `parserParsesChapterListAndChapterImages`
- `extractRuleDecodesLegacySingleFunctionShape`
- `extractRuleDecodesSelectorKindAndFunctionChainShape`
- `urlPatternsDecodeLegacyStringShape`
- `urlPatternsDecodeStructuredTemplateShape`
- `listFieldsDecodeP03DisplayAndMediaFields`
- `detailFieldsDecodeP03SecondLevelPageFields`
- `chapterRuleDecodesCidCodeAliasForURLPlaceholder`

## Notes

- P0-4 only adds semantic nested rule model shape and decode coverage.
- Parser/runtime behavior is unchanged in this step.
- `.xcresult` bundles are ignored by `.gitignore`; this Markdown file keeps the human-readable result.
