# BrowseCraft P0-1 Unit Test Result

Date: 2026-07-03 13:30 JST

## Command

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination id=E94D17BA-093C-4BFF-9AE5-BA586156CDB5 \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P0-1-UnitTests-Run4.xcresult \
  test
```

## Result

- Status: passed
- Target: BrowseCraftTests
- Test count: 6
- Failure count: 0
- Result bundle: `BrowseCraft/TestResults/BrowseCraft-P0-1-UnitTests-Run4.xcresult`

## P0-1 Assertions Added

### extractRuleDecodesLegacySingleFunctionShape

Purpose: prove legacy `ExtractRule` JSON still decodes after adding P0-1 fields.

Assertions:

- `selector == "a.title"`
- `selectorKind == nil`
- `function == .text`
- `functions == nil`
- `regex == "(.+)"`
- `replacement == "$1"`

### extractRuleDecodesSelectorKindAndFunctionChainShape

Purpose: prove P0-1 model can decode selector kind and Yealico-style function chain fields.

Assertions:

- `selector == "img.page"`
- `selectorKind == .css`
- `function == .attr`
- `functions == [.attr, .removingPercentEncoding, .regexReplacement]`
- `param == "data-src"`
- `regex == "^(.+)$"`
- `replacement == "$1"`

## Existing Regression Coverage

- `builtInListRuleParsesComicCards`: passed
- `builtInReaderRuleParsesChapterPages`: passed
- `builtInDetailRuleParsesOnlyScopedChapters`: passed
- `builtInDetailRuleDoesNotFallbackToGlobalChapterLinks`: passed

## Notes

- `Run2` failed before test execution because the new `ExtractFunction` cases made `SwiftSoupRuleParser`'s `switch rule.function` non-exhaustive.
- The parser now explicitly throws `Unsupported extract function` for newly modeled but not-yet-executed P0-1 functions.
- Existing parser behavior for `text`, `html`, `attr`, `raw`, and `url` is unchanged.
