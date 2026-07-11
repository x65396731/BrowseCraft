#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Generating Xcode project with XcodeGen..."
xcodegen generate

for scheme in BrowseCraft.xcodeproj/xcshareddata/xcschemes/*.xcscheme; do
  /usr/bin/perl -0pi -e 's#identifier = "../../BrowseCraft/Configuration/BrowseCraft\.storekit"#identifier = "../BrowseCraft/Configuration/BrowseCraft.storekit"#g' "$scheme"
done

echo "Restoring CocoaPods integration with a clean Ruby gem environment..."
env -u GEM_HOME -u GEM_PATH pod install

echo "Project regeneration complete."
