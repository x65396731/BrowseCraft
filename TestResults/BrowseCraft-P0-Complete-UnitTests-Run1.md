# BrowseCraft P0 Complete Unit Test Result

Date: 2026-07-03 13:49 JST

## Command

```sh
xcodebuild -workspace BrowseCraft/BrowseCraft.xcworkspace \
  -scheme BrowseCraft \
  -destination id=E94D17BA-093C-4BFF-9AE5-BA586156CDB5 \
  -only-testing:BrowseCraftTests \
  -resultBundlePath BrowseCraft/TestResults/BrowseCraft-P0-Complete-UnitTests-Run1.xcresult \
  test
```

## Result

- Status: passed
- Target: BrowseCraftTests
- Test count: 17
- Failure count: 0
- Resolved RulesKit: `BrowseCraftRulesKit @ main (6f54e9b)`
- Result bundle: `BrowseCraft/TestResults/BrowseCraft-P0-Complete-UnitTests-Run1.xcresult`

## Completeness Test Added

### siteRuleDecodesP0CompleteV2Shape

Purpose: decode one complete V2-style `SiteRule` JSON that combines P0-1 through P0-5 model additions while keeping legacy required fields present for migration compatibility.

Coverage:

- Top-level `version`, `site`, `urlPatterns`, `pages`, `ruleSets`, `sharedRequest`, and `flags`.
- Legacy top-level `list`, `detail`, `gallery`, and `video` fields still coexist with V2 fields.
- URL templates for detail, gallery, and search with `idCode`, `cidCode`, `keyword`, and `urlQuery` placeholders.
- Page entries with `ruleRefs`, `displayMode`, page request, and `PageFlag`.
- Shared request, page request, rule request, and image request priority fields.
- `ExtractRule.selectorKind`, `functions`, `fallback`, `regex`, and `replacement`.
- List fields: `largeImage`, `video`, `uploader`, `datetime`, and fallback detail URL.
- Detail fields: `totalImages`, `photoAlbumLink`, and `secondLevelPageURL`.
- Detail child rules: `chapterRule.cidCode`, `tagRule`, `commentRule`, and structured `videoRule`.
- Gallery rule with structured image extraction and image request override.
- Search rule with keyword encoding and list field decoding.

Key assertions:

- `rule.version == 2`
- `rule.site.domain == "example.test"`
- `rule.urlPatterns.detailTemplate.placeholders[0].kind == .idCode`
- `rule.urlPatterns.galleryTemplate.placeholders[0].kind == .cidCode`
- `rule.pages[0].ruleRefs.list == "home-list"`
- `rule.sharedRequest.imageRequest.cookieScope == .image`
- `rule.ruleSets.listRules[0].fields.detailURL.fallback[0].selector == "a.cover"`
- `rule.ruleSets.detailRules[0].fields.totalImages.functions == [.text, .regexReplacement]`
- `rule.ruleSets.detailRules[0].chapterRule.cidCode.param == "data-cid"`
- `rule.ruleSets.galleryRules[0].image.functions == [.attr, .removingPercentEncoding]`
- `rule.ruleSets.searchRules[0].fields.detailURL.function == .url`

## Regression Coverage

The same run also covered the existing parser and P0-specific model tests:

- Built-in list parsing
- Built-in reader parsing
- Scoped detail chapter parsing
- No fallback to global chapter links
- P0-1 extract selector kind and function chain
- P0-2 URL templates
- P0-3 list/detail field additions
- P0-4 semantic nested rules and structured video rule
- P0-5 request priority and legacy request compatibility

## Notes

- This is a model completeness test, not a runtime rule execution test.
- Runtime parser/request/image behavior is unchanged in this step.
- `.xcresult` bundles are ignored by `.gitignore`; this Markdown file keeps the human-readable result.
