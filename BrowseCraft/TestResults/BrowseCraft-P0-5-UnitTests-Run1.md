# BrowseCraft P0-5 Unit Test Result

Date: 2026-07-03 13:45 JST

## Command

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination id=E94D17BA-093C-4BFF-9AE5-BA586156CDB5 \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P0-5-UnitTests-Run1.xcresult \
  test
```

## Result

- Status: passed
- Target: BrowseCraftTests
- Test count: 16
- Failure count: 0
- Resolved RulesKit: `BrowseCraftRulesKit @ main (6f54e9b)`
- Result bundle: `BrowseCraft/TestResults/BrowseCraft-P0-5-UnitTests-Run1.xcresult`

## P0-5 Assertions Added

### requestConfigDecodesP05RequestPriorityShape

Purpose: prove `RequestConfig` can decode request scope, merge policy, cookie priority, cookie scope, and image-specific request configuration.

Assertions:

- `scope == .rule`
- `mergePolicy == .mergeHeadersAndCookies`
- `method == .get`
- `headers["Referer"] == "https://example.test/"`
- `cookiePolicy == .browserThenCustom`
- `cookiePriority == .custom`
- `cookieScope == .rule`
- `charset == .utf8`
- `needsWebView == true`
- `autoScroll == true`
- `imageHeaders["Accept"] == "image/avif,image/webp,image/*"`
- `imageRequest.mergePolicy == .mergeHeaders`
- `imageRequest.headers["Referer"] == "https://image.example/"`
- `imageRequest.cookiePolicy == .browser`
- `imageRequest.cookiePriority == .image`
- `imageRequest.cookieScope == .image`

### requestConfigDecodesLegacyShapeWithoutPriorityFields

Purpose: prove old `RequestConfig` JSON remains decodable when P0-5 priority fields are absent.

Assertions:

- `scope == nil`
- `mergePolicy == nil`
- `cookiePriority == nil`
- `cookieScope == nil`
- `imageRequest == nil`
- `method == .post`
- `headers["Content-Type"] == "application/x-www-form-urlencoded"`
- `body.value == "q=keyword"`
- `cookiePolicy == .custom`
- `charset == .auto`
- `imageHeaders["Referer"] == "https://example.test/"`

## Existing Regression Coverage

The same run also covered the existing parser and P0-1 to P0-4 model tests:

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
- `detailRuleDecodesP04SemanticNestedRules`
- `detailRuleDecodesP04VideoRuleShape`
- `videoRuleDecodesLegacyVideoURLShape`

## Notes

- P0-5 only adds request priority and image request model shape plus decode coverage.
- Runtime request merging behavior is unchanged in this step.
- `.xcresult` bundles are ignored by `.gitignore`; this Markdown file keeps the human-readable result.
