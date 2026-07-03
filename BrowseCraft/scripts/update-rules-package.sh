#!/bin/sh
set -eu

RULES_PACKAGE_IDENTITY="browsecraftruleskit"
RULES_REPO_URL="git@github.com:x65396731/BrowseCraftRulesKit.git"
RULES_BRANCH="main"
SCHEME_NAME="BrowseCraft"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_PATH="${APP_ROOT}/BrowseCraft.xcworkspace"
PROJECT_RESOLVED="${APP_ROOT}/BrowseCraft.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
WORKSPACE_RESOLVED="${APP_ROOT}/BrowseCraft.xcworkspace/xcshareddata/swiftpm/Package.resolved"
LOCAL_RULES_REPO="${APP_ROOT}/../BrowseCraftRulesKit"

log() {
  printf '[update-rules-package] %s\n' "$1"
}

fail() {
  printf '[update-rules-package] ERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_command git
require_command xcodebuild
require_command pod
require_command python3

[ -d "$WORKSPACE_PATH" ] || fail "Workspace not found: $WORKSPACE_PATH"
[ -f "$PROJECT_RESOLVED" ] || fail "Package.resolved not found: $PROJECT_RESOLVED"
[ -f "$WORKSPACE_RESOLVED" ] || fail "Package.resolved not found: $WORKSPACE_RESOLVED"

if [ -d "${LOCAL_RULES_REPO}/.git" ]; then
  dirty_status="$(git -C "$LOCAL_RULES_REPO" status --porcelain)"
  [ -z "$dirty_status" ] || fail "BrowseCraftRulesKit has uncommitted changes. Commit/push or stash them before updating the app package."
fi

log "Reading remote ${RULES_REPO_URL} ${RULES_BRANCH}"
remote_line="$(git ls-remote "$RULES_REPO_URL" "refs/heads/${RULES_BRANCH}")"
target_revision="$(printf '%s' "$remote_line" | awk '{print $1}')"

case "$target_revision" in
  ""|*[!0-9a-f]*)
    fail "Could not read a valid remote revision from ${RULES_REPO_URL} ${RULES_BRANCH}"
    ;;
esac

[ "${#target_revision}" -eq 40 ] || fail "Remote revision is not a 40-character SHA: $target_revision"

if [ -d "${LOCAL_RULES_REPO}/.git" ]; then
  local_revision="$(git -C "$LOCAL_RULES_REPO" rev-parse HEAD)"
  if [ "$local_revision" != "$target_revision" ]; then
    fail "Local BrowseCraftRulesKit HEAD (${local_revision}) does not match remote ${RULES_BRANCH} (${target_revision}). Pull/fetch the rules repo or confirm you meant to use the remote revision."
  fi
fi

log "Target BrowseCraftRulesKit revision: ${target_revision}"

python3 - "$RULES_PACKAGE_IDENTITY" "$RULES_REPO_URL" "$target_revision" "$PROJECT_RESOLVED" "$WORKSPACE_RESOLVED" <<'PY'
import json
import sys
from pathlib import Path

identity = sys.argv[1]
location = sys.argv[2]
target_revision = sys.argv[3]
resolved_paths = [Path(path) for path in sys.argv[4:]]

for resolved_path in resolved_paths:
    payload = json.loads(resolved_path.read_text())
    pins = payload.get("pins", [])
    matched = False

    for pin in pins:
        if pin.get("identity") == identity and pin.get("location") == location:
            state = pin.setdefault("state", {})
            state["branch"] = "main"
            state["revision"] = target_revision
            matched = True

    if not matched:
        raise SystemExit(f"Package pin not found in {resolved_path}: {identity} {location}")

    resolved_path.write_text(json.dumps(payload, indent=2) + "\n")
PY

log "Updated Package.resolved files"

xcodebuild \
  -workspace "$WORKSPACE_PATH" \
  -scheme "$SCHEME_NAME" \
  -resolvePackageDependencies \
  -disablePackageRepositoryCache

python3 - "$RULES_PACKAGE_IDENTITY" "$RULES_REPO_URL" "$target_revision" "$PROJECT_RESOLVED" "$WORKSPACE_RESOLVED" <<'PY'
import json
import sys
from pathlib import Path

identity = sys.argv[1]
location = sys.argv[2]
target_revision = sys.argv[3]
resolved_paths = [Path(path) for path in sys.argv[4:]]

for resolved_path in resolved_paths:
    payload = json.loads(resolved_path.read_text())
    revision = None

    for pin in payload.get("pins", []):
        if pin.get("identity") == identity and pin.get("location") == location:
            revision = pin.get("state", {}).get("revision")
            break

    if revision != target_revision:
        raise SystemExit(
            f"{resolved_path} resolved {revision}, expected {target_revision}"
        )
PY

log "Verified Package.resolved revision: ${target_revision}"

(
  cd "$APP_ROOT"
  pod install
)

log "Done. Package updated and pods installed. No build was run."
