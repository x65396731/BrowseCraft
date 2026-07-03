# BrowseCraft Scripts

## update-rules-package.sh

Use this script after `BrowseCraftRulesKit` has been committed and pushed to `main`.

The script updates the app-side Swift Package pin to the current remote
`BrowseCraftRulesKit` `main` revision, verifies that Xcode resolves the same
revision, then runs `pod install`.

It does not build the app.

```sh
./scripts/update-rules-package.sh
```
