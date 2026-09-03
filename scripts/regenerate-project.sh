#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Generating Xcode project with XcodeGen..."
xcodegen generate

echo "Project regeneration complete."
