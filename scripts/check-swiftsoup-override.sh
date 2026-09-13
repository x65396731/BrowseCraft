#!/bin/bash
# 中文注释：SwiftSoup 走「Core 按 commit 锁定自家 fork + Xcode 本地包覆盖」两条路：
#   - BrowseCraftCore/Package.swift 用 URL + revision 锁定 fork（swift test 走这条）；
#   - BrowseCraft/project.yml 把 ../SwiftSoup 作为本地包加入工程，覆盖整张依赖图里对
#     scinfu/SwiftSoup 的引用（Xcode 构建走这条，Readium 也被指到 fork）。
# 两条路必须指向同一个 commit，否则 swift test 与 Xcode 构建看到的不是同一份解析器。
# 本脚本只做一致性检查，不改任何东西。

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_MANIFEST="$REPOSITORY_ROOT/../BrowseCraftCore/Package.swift"
OVERRIDE_ROOT="$REPOSITORY_ROOT/../SwiftSoup"

if [[ ! -f "$CORE_MANIFEST" ]]; then
  echo "check-swiftsoup-override: 找不到 $CORE_MANIFEST" >&2
  exit 2
fi

pinned_revision="$(
  /usr/bin/awk '
    /url: "https:\/\/github.com\/[^"]*SwiftSoup[^"]*"/ { in_soup = 1 }
    in_soup && /revision: "/ {
      match($0, /revision: "[0-9a-f]+"/)
      print substr($0, RSTART + 11, RLENGTH - 12)
      exit
    }
  ' "$CORE_MANIFEST"
)"

if [[ -z "$pinned_revision" ]]; then
  echo "check-swiftsoup-override: BrowseCraftCore/Package.swift 里没有按 revision 锁定的 SwiftSoup 依赖。" >&2
  echo "  若已切回官方 tag，请同时从 project.yml 删除 SwiftSoup 本地覆盖包，并删除本脚本。" >&2
  exit 1
fi

if [[ ! -d "$OVERRIDE_ROOT/.git" ]]; then
  echo "check-swiftsoup-override: 缺少本地覆盖包 $OVERRIDE_ROOT。" >&2
  echo "  执行：git clone --branch browsecraft/text-whitespace-fix git@github.com:x65396731/SwiftSoup.git \"$OVERRIDE_ROOT\"" >&2
  exit 1
fi

local_revision="$(git -C "$OVERRIDE_ROOT" rev-parse HEAD)"

if [[ "$local_revision" != "$pinned_revision" ]]; then
  echo "check-swiftsoup-override: 本地覆盖包与 Core 锁定的 commit 不一致。" >&2
  echo "  Core 锁定:  $pinned_revision" >&2
  echo "  ../SwiftSoup: $local_revision" >&2
  echo "  执行：git -C \"$OVERRIDE_ROOT\" fetch origin && git -C \"$OVERRIDE_ROOT\" checkout $pinned_revision" >&2
  exit 1
fi

if [[ -n "$(git -C "$OVERRIDE_ROOT" status --porcelain)" ]]; then
  echo "check-swiftsoup-override: 本地覆盖包有未提交改动，Xcode 会用改动后的源码，与 Core 锁定的 commit 不再等价。" >&2
  git -C "$OVERRIDE_ROOT" status --short >&2
  exit 1
fi

echo "check-swiftsoup-override: OK（$pinned_revision）"
