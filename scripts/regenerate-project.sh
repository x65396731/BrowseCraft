#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

# CocoaPods needs a UTF-8 locale; without one it aborts with
# "Unicode Normalization not appropriate for ASCII-8BIT" and leaves the project
# XcodeGen just rewrote without any [CP] phases.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

echo "Generating Xcode project with XcodeGen..."
xcodegen generate

echo "Restoring CocoaPods integration with a clean Ruby gem environment..."
if ! env -u GEM_HOME -u GEM_PATH pod install; then
  echo ""
  echo "ERROR: pod install failed. BrowseCraft.xcodeproj is now missing the CocoaPods phases;"
  echo "       do not build or archive until \`pod install\` succeeds (scripts/check-pods-integration.sh will refuse)."
  exit 1
fi

echo "Project regeneration complete."
