#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$REPOSITORY_ROOT/BrowseCraft"
DOMAIN_FRAMEWORK_ROOT="$REPOSITORY_ROOT/BrowseCraftDomain"

search_swift() {
  local directory="$1"
  local pattern="$2"
  local status

  if /usr/bin/grep -R -nHE --include='*.swift' "$pattern" "$directory"; then
    return 0
  else
    status=$?
  fi

  # grep uses 1 for a clean "no matches" result and values above 1 for real errors.
  if [[ "$status" -eq 1 ]]; then
    return 0
  fi
  return "$status"
}

exclude_matches() {
  local matches="$1"
  shift
  local output=''
  local match
  local excluded_pattern

  while IFS= read -r match; do
    [[ -z "$match" ]] && continue

    local is_excluded=false
    for excluded_pattern in "$@"; do
      if [[ "$match" == *"$excluded_pattern"* ]]; then
        is_excluded=true
        break
      fi
    done

    if [[ "$is_excluded" == false ]]; then
      if [[ -n "$output" ]]; then
        output+=$'\n'
      fi
      output+="$match"
    fi
  done <<< "$matches"

  printf '%s' "$output"
}

fail_if_imported() {
  local directory="$1"
  local pattern="$2"
  local label="$3"
  local matches

  matches="$(search_swift "$directory" "^import ($pattern)$")"
  if [[ -n "$matches" ]]; then
    echo "Architecture boundary violation: $label"
    echo "$matches"
    exit 1
  fi
}

fail_if_imported \
  "$APP_ROOT/Domain" \
  'UIKit|SwiftUI|StoreKit|GRDB|Alamofire|Nuke|SwiftSoup|BrowseCraftAPIKit' \
  'Domain must remain framework-agnostic.'

fail_if_imported \
  "$DOMAIN_FRAMEWORK_ROOT" \
  'UIKit|SwiftUI|StoreKit|GRDB|Alamofire|Nuke|SwiftSoup|BrowseCraftAPIKit|BrowseCraftCore' \
  'BrowseCraftDomain must remain dependency-free beyond Foundation.'

fail_if_imported \
  "$APP_ROOT/Application" \
  'UIKit|SwiftUI|StoreKit|GRDB|Alamofire|Nuke|SwiftSoup|BrowseCraftAPIKit' \
  'Application must depend on ports and domain values, not UI or infrastructure frameworks.'

matches="$(search_swift "$APP_ROOT" '(^|[^[:alnum:]_])print[[:space:]]*\(')"
if [[ -n "$matches" ]]; then
  echo 'Architecture boundary violation: use AppLog/AppDebugLog instead of print.'
  echo "$matches"
  exit 1
fi

api_kit_matches="$(search_swift "$APP_ROOT" '^import BrowseCraftAPIKit$')"
api_kit_violations="$(
  exclude_matches \
    "$api_kit_matches" \
    '/Infrastructure/' \
    '/App/AppContainer.swift:'
)"
if [[ -n "$api_kit_violations" ]]; then
  echo 'Architecture boundary violation: BrowseCraftAPIKit escaped its adapter/composition boundary.'
  echo "$api_kit_violations"
  exit 1
fi

CORE_ROOT="$REPOSITORY_ROOT/../BrowseCraftCore/Sources/BrowseCraftCore"
if [[ -d "$CORE_ROOT" ]]; then
  swift_soup_matches="$(search_swift "$CORE_ROOT" '^import SwiftSoup$')"
  swift_soup_violations="$(
    exclude_matches \
      "$swift_soup_matches" \
      '/Parsing/Document/HTML/SwiftSoupHTMLDocumentParser.swift:' \
      '/Parsing/Discovery/DefaultSourceDiscoveryAnalyzer.swift:'
  )"
  if [[ -n "$swift_soup_violations" ]]; then
    echo 'Architecture boundary violation: SwiftSoup escaped its named Core adapters.'
    echo "$swift_soup_violations"
    exit 1
  fi
fi

echo 'Architecture boundaries are clean.'
