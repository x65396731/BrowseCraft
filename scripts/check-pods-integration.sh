#!/bin/bash

# XcodeGen rewrites the project file without the CocoaPods phases; only a
# following `pod install` puts them back. Building from the half-regenerated
# project produces an app whose executable links Alamofire/GRDB/Nuke/NukeUI/Gifu
# but does not embed them (dyld crash on launch, ITMS-90863 on upload), so fail
# the build before that can happen.

set -euo pipefail

project_file="${PROJECT_FILE_PATH:-}/project.pbxproj"
target_name="${TARGET_NAME:-BrowseCraft}"

if [[ ! -f "$project_file" ]]; then
  echo "error: check-pods-integration.sh could not find $project_file"
  exit 1
fi

if ! /usr/bin/grep -q '\[CP\] Embed Pods Frameworks' "$project_file"; then
  echo "error: CocoaPods is not integrated into ${target_name} (no '[CP] Embed Pods Frameworks' phase). Run scripts/regenerate-project.sh, then reopen BrowseCraft.xcworkspace."
  exit 1
fi

if [[ ! -f "${PODS_ROOT:-${SRCROOT}/Pods}/Manifest.lock" ]]; then
  echo "error: Pods/Manifest.lock is missing. Run scripts/regenerate-project.sh."
  exit 1
fi

echo 'CocoaPods integration is present.'
