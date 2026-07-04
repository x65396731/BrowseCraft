# BrowseCraft P3-7.6 Library Runtime Refresh Build-For-Testing Run 1

- Date: 2026-07-04
- Scope: P3-7.6 Library list refresh runtime pilot.
- Command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -workspace /Users/xiefei/BrowseCraft/BrowseCraft.xcworkspace -scheme BrowseCraft -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/BrowseCraft-P3-7-6-BuildForTesting-DerivedData`
- Result: Passed.
- Xcode result: `** TEST BUILD SUCCEEDED **`.
- Notes:
  - This run compiled the app and test bundles but did not execute tests or launch the app.
  - The first sandboxed attempt failed before build because CoreSimulator services are unavailable inside the sandbox.
  - After noticing `Application/Runtime/README.md` was being treated as an app resource, `project.yml` now excludes `**/*.md` from the App target and `scripts/regenerate-project.sh` was rerun.
  - Generated project scan confirmed no `README.md` resource reference remains.
