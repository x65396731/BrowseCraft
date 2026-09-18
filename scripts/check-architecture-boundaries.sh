#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$REPOSITORY_ROOT/BrowseCraft"
CORE_ROOT="$REPOSITORY_ROOT/../BrowseCraftCore/Sources/BrowseCraftCore"
RULE_MODELS_ROOT="$REPOSITORY_ROOT/../BrowseCraftCore/Sources/BrowseCraftRuleModels"
DOMAIN_PACKAGE_ROOT="$REPOSITORY_ROOT/../BrowseCraftDomain/Sources/BrowseCraftDomain"
RUNTIME_PACKAGE_ROOT="$REPOSITORY_ROOT/../BrowseCraftRuntime/Sources/BrowseCraftRuntime"
API_KIT_PACKAGE_ROOT="$REPOSITORY_ROOT/../BrowseCraftAPIKit/Sources/BrowseCraftAPIKit"
EXEMPTIONS_FILE="$REPOSITORY_ROOT/scripts/architecture-boundary-exemptions.txt"

# Every spelling of an import statement that brings module X into a file:
#   import X            @preconcurrency import X      @_exported import X
#   import struct X.Y   import X.Submodule            @testable import X
# The old check matched only the bare `^import X$` form, which let the
# annotated and scoped forms through unnoticed.
IMPORT_PREFIX='^[[:space:]]*(@preconcurrency[[:space:]]+|@_exported[[:space:]]+|@_implementationOnly[[:space:]]+|@testable[[:space:]]+|@_spi\([A-Za-z0-9_]+\)[[:space:]]+)*import([[:space:]]+(struct|class|enum|protocol|actor|func|var|let|typealias))?[[:space:]]+'
IMPORT_SUFFIX='(\.[A-Za-z_][A-Za-z0-9_.]*)?[[:space:]]*$'

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

# Reads grep-style `path:line:content` matches on stdin and blanks out every
# token that the exemptions file registers for that path, so a line whose only
# offending references are registered no longer matches the caller's pattern.
# Paths in the exemptions file are relative to the repository root; package
# paths use `../BrowseCraftXxx/...`, which is how the roots above are spelled.
apply_exemptions() {
  local script=''
  local file token

  if [[ ! -f "$EXEMPTIONS_FILE" ]]; then
    cat
    return 0
  fi

  while read -r file token; do
    [[ -z "$file" || "$file" == \#* ]] && continue
    script+="\\#^${REPOSITORY_ROOT}/${file}:#s/(^|[^A-Za-z0-9_])${token}([^A-Za-z0-9_]|\$)/\\1\\2/g;"
  done < "$EXEMPTIONS_FILE"

  if [[ -z "$script" ]]; then
    cat
    return 0
  fi
  sed -E "$script"
}

fail_if_imported() {
  local directory="$1"
  local pattern="$2"
  local label="$3"
  local matches

  matches="$(search_swift "$directory" "${IMPORT_PREFIX}(${pattern})${IMPORT_SUFFIX}")"
  if [[ -n "$matches" ]]; then
    echo "Architecture boundary violation: $label"
    echo "$matches"
    exit 1
  fi
}

FORBIDDEN_FRAMEWORKS='UIKit|SwiftUI|StoreKit|GRDB|Alamofire|Nuke|SwiftSoup|BrowseCraftAPIKit|WebKit|AVFoundation|CloudKit|Combine|ReadiumShared|ReadiumStreamer|ReadiumNavigator|ReadiumAdapterGCDWebServer|MediaPlayer'

fail_if_imported \
  "$APP_ROOT/Domain" \
  "$FORBIDDEN_FRAMEWORKS" \
  'Domain must remain framework-agnostic.'

if [[ -d "$DOMAIN_PACKAGE_ROOT" ]]; then
fail_if_imported \
  "$DOMAIN_PACKAGE_ROOT" \
  "$FORBIDDEN_FRAMEWORKS" \
  'BrowseCraftDomain may depend only on Foundation and BrowseCraftCore.'
fi

fail_if_imported \
  "$APP_ROOT/Application" \
  "$FORBIDDEN_FRAMEWORKS" \
  'Application must depend on ports and domain values, not UI or infrastructure frameworks.'

# Import checks cannot see references between layers of the same module, so the
# type names declared at top level in one layer are also searched in layers that
# may not depend on it. Comments and string literals are stripped before matching.
declared_types() {
  local directory="$1"
  /usr/bin/grep -R -h -o -E --include='*.swift' \
    '^(public |internal |private |fileprivate |package |open |final |indirect |nonisolated |@MainActor |@frozen |@Observable |@propertyWrapper |@dynamicMemberLookup |@objc |@objcMembers |@usableFromInline )*(final )?(class|struct|enum|protocol|actor) [A-Z][A-Za-z0-9_]+' \
    "$directory" 2>/dev/null | awk '{print $NF}' | sort -u
}

fail_if_types_referenced() {
  local owner_directory="$1"
  local user_directory="$2"
  local label="$3"
  local owner_types user_types pattern matches

  owner_types="$(declared_types "$owner_directory")"
  [[ -z "$owner_types" ]] && return 0
  user_types="$(declared_types "$user_directory")"
  if [[ -n "$user_types" ]]; then
    # A name declared in both layers resolves to the local declaration.
    owner_types="$(comm -23 <(printf '%s\n' "$owner_types") <(printf '%s\n' "$user_types"))"
  fi
  [[ -z "$owner_types" ]] && return 0

  pattern="($(printf '%s\n' "$owner_types" | paste -s -d '|' -))"
  matches="$(
    /usr/bin/grep -R -n -H -w -E --include='*.swift' "$pattern" "$user_directory" 2>/dev/null \
      | sed -E 's/"([^"\\]|\\.)*"//g; s#//.*$##' \
      | apply_exemptions \
      | /usr/bin/grep -w -E "$pattern" || true
  )"
  if [[ -n "$matches" ]]; then
    echo "Architecture boundary violation: $label"
    echo "$matches"
    exit 1
  fi
}

for layer in Application Infrastructure Features App Shared; do
  fail_if_types_referenced "$APP_ROOT/$layer" "$APP_ROOT/Domain" \
    "Domain must not reference $layer types."
done
for layer in Features Infrastructure App; do
  fail_if_types_referenced "$APP_ROOT/$layer" "$APP_ROOT/Application" \
    "Application must not reference $layer types; move the contract into Application or Domain."
done
for layer in Features App; do
  fail_if_types_referenced "$APP_ROOT/$layer" "$APP_ROOT/Infrastructure" \
    "Infrastructure must not reference $layer types."
done
fail_if_types_referenced "$APP_ROOT/App" "$APP_ROOT/Features" \
  'Features must not reference composition-root (App) types.'
fail_if_types_referenced "$APP_ROOT/Infrastructure" "$APP_ROOT/Features" \
  'Features must not construct Infrastructure types; inject them through Application ports.'
fail_if_types_referenced "$APP_ROOT/App" "$APP_ROOT/Shared" \
  'Shared must not reference composition-root (App) types.'
fail_if_types_referenced "$APP_ROOT/Features" "$APP_ROOT/Shared" \
  'Shared must not reference Feature types.'
fail_if_types_referenced "$APP_ROOT/Application" "$APP_ROOT/Shared" \
  'Shared must not reference Application types; it sits below Application.'
fail_if_types_referenced "$APP_ROOT/Infrastructure" "$APP_ROOT/Shared" \
  'Shared must not reference Infrastructure types.'

# Token bans apply to the app and to every package source tree.
fail_if_token_used() {
  local pattern="$1"
  local label="$2"
  local directory matches all_matches=''

  for directory in "$APP_ROOT" "$CORE_ROOT" "$RULE_MODELS_ROOT" "$DOMAIN_PACKAGE_ROOT" "$RUNTIME_PACKAGE_ROOT" "$API_KIT_PACKAGE_ROOT"; do
    [[ -d "$directory" ]] || continue
    matches="$(search_swift "$directory" "$pattern" | apply_exemptions | /usr/bin/grep -E "$pattern" || true)"
    if [[ -n "$matches" ]]; then
      all_matches+="$matches"$'\n'
    fi
  done

  if [[ -n "$all_matches" ]]; then
    echo "Architecture boundary violation: $label"
    printf '%s' "$all_matches"
    exit 1
  fi
}

fail_if_token_used '(^|[^[:alnum:]_])print[[:space:]]*\(' 'use AppLog/AppDebugLog instead of print.'
fail_if_token_used '(^|[^[:alnum:]_])try!' 'do not use try!; propagate or handle the error (register a reviewed literal-pattern exception in scripts/architecture-boundary-exemptions.txt).'

api_kit_matches="$(search_swift "$APP_ROOT" "${IMPORT_PREFIX}BrowseCraftAPIKit${IMPORT_SUFFIX}")"
api_kit_violations="$(
  exclude_matches \
    "$api_kit_matches" \
    '/Infrastructure/' \
    '/App/Composition/'
)"
if [[ -n "$api_kit_violations" ]]; then
  echo 'Architecture boundary violation: BrowseCraftAPIKit escaped its adapter/composition boundary.'
  echo "$api_kit_violations"
  exit 1
fi

# BrowseCraftRuleModels is the SwiftSoup-free model layer that BrowseCraftDomain links; no
# file in it may import SwiftSoup or reach into the parsing target.
if [[ -d "$RULE_MODELS_ROOT" ]]; then
  fail_if_imported \
    "$RULE_MODELS_ROOT" \
    'SwiftSoup|BrowseCraftCore' \
    'BrowseCraftRuleModels must stay free of SwiftSoup and of the parsing target.'
fi

if [[ -d "$CORE_ROOT" ]]; then
  swift_soup_matches="$(search_swift "$CORE_ROOT" "${IMPORT_PREFIX}SwiftSoup${IMPORT_SUFFIX}")"
  swift_soup_violations="$(
    exclude_matches \
      "$swift_soup_matches" \
      '/Parsing/Document/HTML/SwiftSoupHTMLDocumentParser.swift:' \
      '/Parsing/Discovery/DefaultSourceDiscoveryAnalyzer.swift:' \
      '/Parsing/Discovery/DefaultSourceListStructureObserver.swift:'
  )"
  if [[ -n "$swift_soup_violations" ]]; then
    echo 'Architecture boundary violation: SwiftSoup escaped its named Core adapters.'
    echo "$swift_soup_violations"
    exit 1
  fi
fi

# 中文注释：Swift 6 语言模式闸门（2026-09-18）。切换前已量过代价为零，它把此前
# 「complete 严格并发 + 警告为零」这一当下状态固化成编译错误。这个取值一旦被调回
# 5.x，全部数据竞争诊断会退回警告，而警告不会让任何构建失败——没人会发现。
# 因此把它写成显式声明加闸门：工程与四个包各自声明一次，这里逐一核对。
app_swift_version="$(sed -n 's/^ *SWIFT_VERSION: *"\(.*\)"/\1/p' "$REPOSITORY_ROOT/project.yml" | head -1)"
if [[ "$app_swift_version" != "6.0" ]]; then
  echo "Architecture boundary violation: project.yml 的 SWIFT_VERSION 是 '${app_swift_version}'，应为 6.0。"
  echo '调低语言模式会把数据竞争诊断降级为警告；要改必须连同理由一起改这条闸门。'
  exit 1
fi

for package_name in BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit; do
  package_manifest="$REPOSITORY_ROOT/../$package_name/Package.swift"
  [[ -f "$package_manifest" ]] || continue
  if ! grep -q '^// swift-tools-version: 6\.0' "$package_manifest"; then
    echo "Architecture boundary violation: $package_name 的 swift-tools-version 不是 6.0。"
    exit 1
  fi
  if ! grep -q 'swiftLanguageMode(\.v6)' "$package_manifest"; then
    echo "Architecture boundary violation: $package_name 没有显式声明 .swiftLanguageMode(.v6)。"
    echo '这里要的是显式声明而不是靠 tools-version 6.0 的隐含默认——隐含默认改了没人看得出来。'
    exit 1
  fi
done

echo 'Architecture boundaries are clean.'
