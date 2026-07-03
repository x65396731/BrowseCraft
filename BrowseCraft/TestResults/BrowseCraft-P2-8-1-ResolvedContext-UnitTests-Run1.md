# BrowseCraft P2-8.1 Resolved Context Unit Tests Run 1

- Date: 2026-07-04
- Device: iPhone 17 Pro Simulator, iOS 26.5
- Environment: BrowseCraft, macOS 26.5.1
- Result: Passed

## Scope

P2-8.1 adds resolved debug contexts for Detail/Reader Debug:

- `ResolvedSiteRule.primaryDetailContext`
- `ResolvedSiteRule.primaryReaderContext`
- `ResolvedSiteRule.detailRule(for:)`
- `ResolvedSiteRule.galleryRule(for:)`

The tests cover V2 page/rule/request binding and legacy fallback context availability.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests/SiteRuleV2CompletenessTests -resultBundlePath /private/tmp/BrowseCraft-P2-8-1-ResolvedContext.xcresult
```

- Result: Passed
- Total tests: 12
- Passed tests: 12
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-8-1-ResolvedContext.xcresult`

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet -workspace /Users/xiefei/Desktop/test-git/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BrowseCraftTests -resultBundlePath /private/tmp/BrowseCraft-P2-8-1-Full.xcresult
```

- Result: Passed
- Total tests: 91
- Passed tests: 91
- Failed tests: 0
- Skipped tests: 0
- Result bundle: `/private/tmp/BrowseCraft-P2-8-1-Full.xcresult`

## Notes

- No `xcodegen generate` was needed for this run.
- No `BrowseCraft.xcodeproj/project.pbxproj` change was produced by this run.
- The targeted run showed existing non-fatal redundant `try` warnings in `SwiftSoupRuleParser`; they are unrelated to P2-8.1.
- `.xcresult` bundles are temporary local artifacts; this Markdown file is the retained test record.
