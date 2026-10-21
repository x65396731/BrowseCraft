#!/bin/zsh
# 中文注释：Xcode Cloud 克隆完本仓库后执行（文件名与位置由 Xcode Cloud 约定：ci_scripts/ 与工程同级）。
# 本机开发不跑它。它做三件事，让云端的目录布局与本机一致：
#   1. 把五个本地包仓库克隆到仓库的上一级目录（project.yml 与边界闸门都按 ../BrowseCraftXxx 引用）；
#   2. 写入生产目录密钥的 *.local.xcconfig（本机这几份文件被 gitignore，云端从加密环境变量生成）；
#   3. 用锁定版本的 XcodeGen 生成工程（.xcodeproj 不入库，只跟踪 Package.resolved）。
#
# 需要在 Xcode Cloud 工作流里配置的加密环境变量（Secret）：
#   BC_GITHUB_TOKEN              对五个包仓库只有 Contents: Read 的 GitHub fine-grained token
#   BC_CATALOG_ENCRYPTION_KEYS   与本机 CatalogEncryption.release.local.xcconfig 等号右侧相同的值
set -euo pipefail

REPOSITORY_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
WORKSPACE_ROOT="$(dirname "$REPOSITORY_ROOT")"
GITHUB_OWNER="x65396731"
SIBLING_PACKAGES=(BrowseCraftLog BrowseCraftCore BrowseCraftDomain BrowseCraftRuntime BrowseCraftAPIKit)
# 中文注释：与本机 `xcodegen --version` 保持一致；升级本机 XcodeGen 时同步改这里。
XCODEGEN_VERSION="2.46.0"

if [[ -z "${BC_GITHUB_TOKEN:-}" ]]; then
  echo "error: 缺少加密环境变量 BC_GITHUB_TOKEN，无法克隆私有包仓库。" >&2
  exit 1
fi

echo "== 克隆本地包仓库到 $WORKSPACE_ROOT"
for package in "${SIBLING_PACKAGES[@]}"; do
  destination="$WORKSPACE_ROOT/$package"
  rm -rf "$destination"
  git clone --quiet --depth 1 \
    "https://x-access-token:${BC_GITHUB_TOKEN}@github.com/${GITHUB_OWNER}/${package}.git" \
    "$destination"
  # 中文注释：去掉 remote URL 里的令牌，避免后续步骤的日志把它带出来。
  git -C "$destination" remote set-url origin "https://github.com/${GITHUB_OWNER}/${package}.git"
  echo "$package @ $(git -C "$destination" rev-parse --short HEAD)"
done

echo "== 写入目录密钥 local xcconfig"
# 中文注释：服务器已切到 prod-v1，没有生产密钥的包解不开目录；缺密钥直接失败，免得发出坏包。
if [[ -z "${BC_CATALOG_ENCRYPTION_KEYS:-}" ]]; then
  echo "error: 缺少加密环境变量 BC_CATALOG_ENCRYPTION_KEYS。" >&2
  exit 1
fi
config_dir="$REPOSITORY_ROOT/Config"
print -r -- "BROWSECRAFT_CATALOG_ENCRYPTION_KEYS = ${BC_CATALOG_ENCRYPTION_KEYS}" \
  > "$config_dir/CatalogEncryption.release.local.xcconfig"
print -r -- '#include "CatalogEncryption.release.local.xcconfig"' \
  > "$config_dir/CatalogEncryption.debug.local.xcconfig"
print -r -- '#include "CatalogEncryption.release.local.xcconfig"' \
  > "$config_dir/CatalogEncryption.testflight.local.xcconfig"
echo "已写入（值不打印）。"

echo "== 生成工程（XcodeGen $XCODEGEN_VERSION）"
xcodegen_dir="$(mktemp -d)"
curl --fail --silent --show-error --location \
  "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip" \
  --output "$xcodegen_dir/xcodegen.zip"
unzip -q "$xcodegen_dir/xcodegen.zip" -d "$xcodegen_dir"
"$xcodegen_dir/xcodegen/bin/xcodegen" generate --spec "$REPOSITORY_ROOT/project.yml"
