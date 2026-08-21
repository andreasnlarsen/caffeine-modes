#!/bin/zsh
set -euo pipefail

identity="${DEVELOPER_ID_APPLICATION:-Developer ID Application: LEAD MEDIA AS (D79LWN85PJ)}"
profile="${NOTARY_PROFILE:-notchfocus-notary}"

security find-identity -v -p codesigning | rg -F "$identity" >/dev/null
xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
printf 'PASS RELEASE PREREQUISITES\n'
