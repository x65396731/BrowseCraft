# BrowseCraftCore P3-8.5a SourceItemReference Build Run 1

- Date: 2026-07-04
- Scope: P3-8.5a Core Detail/Reader handoff contract model.
- Result: Passed.

## Changes Verified

- Added Core `SourceItemReference` as the first Detail/Reader handoff contract model.
- Added `SourceItemHandoffIntent` for normal detail handoff and direct-reader handoff.
- Added `SourceItemListContext` to carry source/page/tab/section/rule context without importing App-only `ListContext`.
- Updated Core `ContentType` to conform to `Sendable` so it can be used by runtime handoff models.
- The new model depends only on Foundation and existing BrowseCraftCore runtime/source models.

## Commands

```sh
swift build
```

```sh
git -C /Users/xiefei/Desktop/BrowseCraftCore diff --check
```

## Result Summary

- `swift build`: passed.
- `git diff --check`: passed.

## Notes

- The first sandboxed `swift build` attempt was blocked by SwiftPM/clang cache and `.build` write permissions.
- The authorized rerun completed successfully.
- No App code was changed for P3-8.5a.
- No Core tests were added in this node; P3-8.5b is reserved for Codable / Hashable / handoff intent tests.
