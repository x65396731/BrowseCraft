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

if [[ "$rewarded_ad_unit_id" != "$GOOGLE_SAMPLE_PUBLISHER_ID"* ]]; then
  echo 'Ad configuration is clean.'
  exit 0
fi

if [[ "$environment_name" == "PROD" && "$build_action" == "install" ]]; then
  echo "error: PROD archive still uses Google's sample rewarded ad unit ($rewarded_ad_unit_id). Set BROWSECRAFT_REWARDED_AD_UNIT_ID for the Release config in project.yml before archiving."
  exit 1
fi

echo "warning: Rewarded ad unit is Google's sample unit ($rewarded_ad_unit_id) for environment ${environment_name:-unknown}; a PROD archive will fail until it is replaced."
