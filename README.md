# BrowseCraft

BrowseCraft is an iOS reader app driven by custom source rules.

## Project Layout

- `BrowseCraft/`: App source code.
- `BrowseCraftTests/`: Unit tests.
- `BrowseCraftUITests/`: UI tests.
- `scripts/`: Project maintenance scripts.
- `TestResults/`: Markdown summaries for retained test runs.

## Project Regeneration

Dependencies are managed with Swift Package Manager. Regenerate the project after adding, moving or removing source files:

```sh
./scripts/regenerate-project.sh
```
