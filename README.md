# BrowseCraft

BrowseCraft is an iOS reader app driven by custom source rules.

## Project Layout

- `BrowseCraft/`: App source code.
- `BrowseCraftTests/`: Unit tests.
- `BrowseCraftUITests/`: UI tests.
- `scripts/`: Project maintenance scripts.
- `TestResults/`: Markdown summaries for retained test runs.

## Project Regeneration

Use the project script instead of running `xcodegen generate` and `pod install` manually:

```sh
./scripts/regenerate-project.sh
```
