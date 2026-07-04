# BrowseCraft P3-9.7a Physical Structure Hygiene - Run 1

Date: 2026-07-04

## Scope

- Confirm whether `BrowseCraft/Application/Adapters/` is an empty physical residual.
- Remove the empty directory if it has no files.
- Verify there is no Bridge / Adapter naming drift.
- Record the current `Application` physical structure before P3-9.7b.

## Result

- `BrowseCraft/Application/Adapters/` contained no files or subdirectories.
- Removed the empty `Adapters` directory from the working tree.
- This directory was not tracked by git, so removal does not appear as a tracked diff.

## Current Application Structure

```text
BrowseCraft/Application
BrowseCraft/Application/Runtime
BrowseCraft/Application/Runtime/Debug
BrowseCraft/Application/Runtime/Rule
BrowseCraft/Application/UseCases
```

## Static Checks

```sh
find BrowseCraft/Application -maxdepth 3 -type d | sort
rg -n "Bridge|Adapter|unsupportedPersistedSourceKind" BrowseCraft BrowseCraftTests /Users/xiefei/Desktop/BrowseCraftCore/Sources /Users/xiefei/Desktop/BrowseCraftCore/Tests
git diff --check
```

## Static Check Result

- Application structure no longer includes `Application/Adapters`.
- `Bridge|Adapter|unsupportedPersistedSourceKind`: no matches.
- `git diff --check`: passed after removing one trailing whitespace line from the P3-9 plan file.

## XcodeGen / Pods / Tests

- No Swift files were added, moved, or edited.
- Did not run `./scripts/regenerate-project.sh`.
- Did not run `pod install`.
- Did not run xcodebuild tests.

## Next

- Next subsection: `P3-9.7b RefreshSourceUseCase boundary audit`.
- Plan update needed: no. P3-9.7a matched the existing plan; `Application/Adapters` was empty as expected.
