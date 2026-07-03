# BrowseCraft P1-2 Function Chains Unit Test Result

Date: 2026-07-03 14:12 JST

## Command

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination id=E94D17BA-093C-4BFF-9AE5-BA586156CDB5 \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P1-2-FunctionChains-UnitTests-Run1.xcresult \
  test
```

## Result

- Status: passed
- Target: BrowseCraftTests
- Test count: 18
- Failure count: 0
- Resolved RulesKit: `BrowseCraftRulesKit @ main (6f54e9b)`
- Result bundle: `BrowseCraft/TestResults/BrowseCraft-P1-2-FunctionChains-UnitTests-Run1.xcresult`

## Function Chain Coverage

### v2ChapterRulesApplyFunctionChains

Purpose: prove V2 `ExtractRule.functions` are executed in order through the public detail chapter parsing path.

Assertions:

- Title rule runs `text -> regexReplacement`.
- URL rule runs `url -> removingPercentEncoding`.
- The decoded relative URL is still resolved through `URLResolvingService`.
- Final chapter title is `第01话`.
- Final chapter URL is `https://example.test/reader/one`.

## Regression Coverage

The same run also covered the existing parser and model tests:

- ExtractRule model compatibility and function-chain decode shape
- URL template model decode
- List, detail, chapter field model decode
- Semantic tag/comment/video rule decode
- Request priority and image request model decode
- Complete V2 SiteRule decode with legacy fields
- Built-in list parser regression
- Built-in detail parser regression
- Built-in reader parser regression

## Notes

- Runtime function chains now support source functions and lightweight string transforms.
- `replace` and `decompressFromBase64` remain explicitly unsupported in the parser.
- `.xcresult` bundles are ignored by `.gitignore`; this Markdown file keeps the human-readable result.
