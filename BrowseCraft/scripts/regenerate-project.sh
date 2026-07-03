#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Generating Xcode project with XcodeGen..."
xcodegen generate

echo "Restoring CocoaPods integration with a clean Ruby gem environment..."
env -u GEM_HOME -u GEM_PATH pod install

echo "Project regeneration complete."
