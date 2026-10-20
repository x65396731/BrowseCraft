#!/bin/bash

# Google's sample ad units are fine for Debug and TestFlight builds, but a PROD
# App Store archive must ship a real rewarded ad unit. Build settings from
# project.yml arrive here as environment variables; ACTION is "install" for
# archives and "build" for everything else.

set -euo pipefail

GOOGLE_SAMPLE_PUBLISHER_ID="ca-app-pub-3940256099942544"

environment_name="${BROWSECRAFT_ENVIRONMENT_NAME:-}"
rewarded_ad_unit_id="${BROWSECRAFT_REWARDED_AD_UNIT_ID:-}"
build_action="${ACTION:-build}"
catalog_encryption_keys="${BROWSECRAFT_CATALOG_ENCRYPTION_KEYS:-}"

# 中文注释：tracked 的 Config/CatalogEncryption.release.xcconfig 把目录解密密钥置空，只 #include? 一份
# gitignore 的 *.local.xcconfig。没有那份文件的机器归档出的 PROD 包里密钥为空，每条密文规则都是
# missingKey、目录整表失败，而构建期零提示（2026-10-20 审计发布前清单第 1 项）。这里在 PROD 归档时
# 断言密钥非空且含 prod- 前缀；Debug / TestFlight 仍可用 tracked 的 test-v1。
if [[ "$environment_name" == "PROD" && "$build_action" == "install" ]]; then
  if [[ -z "$catalog_encryption_keys" || "$catalog_encryption_keys" != *prod-* ]]; then
    echo "error: PROD archive has no production catalog encryption key (BROWSECRAFT_CATALOG_ENCRYPTION_KEYS is empty or lacks a prod- key). Create Config/CatalogEncryption.release.local.xcconfig on this machine before archiving."
    exit 1
  fi
fi

if [[ "$rewarded_ad_unit_id" != "$GOOGLE_SAMPLE_PUBLISHER_ID"* ]]; then
  echo 'Ad configuration is clean.'
  exit 0
fi

if [[ "$environment_name" == "PROD" && "$build_action" == "install" ]]; then
  echo "error: PROD archive still uses Google's sample rewarded ad unit ($rewarded_ad_unit_id). Set BROWSECRAFT_REWARDED_AD_UNIT_ID for the Release config in project.yml before archiving."
  exit 1
fi

echo "warning: Rewarded ad unit is Google's sample unit ($rewarded_ad_unit_id) for environment ${environment_name:-unknown}; a PROD archive will fail until it is replaced."
