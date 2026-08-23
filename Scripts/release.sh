#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
identity="${DEVELOPER_ID_APPLICATION:-Developer ID Application: LEAD MEDIA AS (D79LWN85PJ)}"
profile="${NOTARY_PROFILE:-notchfocus-notary}"
version="${APP_VERSION:-1.1.1}"
build_number="${BUILD_NUMBER:-5}"
dmg="$project_root/dist/Caffeine-Modes-$version.dmg"
stage="$project_root/dist/dmg-root"
notary_zip="$project_root/dist/Caffeine-Modes-$version-notarize.zip"

DEVELOPER_ID_APPLICATION="$identity" NOTARY_PROFILE="$profile" "$project_root/Scripts/check-release-prerequisites.sh" >/dev/null
CODE_SIGN_IDENTITY="$identity" APP_VERSION="$version" BUILD_NUMBER="$build_number" "$project_root/Scripts/build-app.sh" >/dev/null

if [[ -e "$notary_zip" ]]; then
    rm "$notary_zip"
fi
ditto -c -k --keepParent "$project_root/build/Caffeine Modes.app" "$notary_zip"
xcrun notarytool submit "$notary_zip" \
    --keychain-profile "$profile" \
    --wait \
    --output-format json > "$project_root/dist/app-notarization-info.json"
rg -q '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$project_root/dist/app-notarization-info.json"
xcrun stapler staple "$project_root/build/Caffeine Modes.app"
xcrun stapler validate "$project_root/build/Caffeine Modes.app"
rm "$notary_zip"

if [[ -e "$stage" ]]; then
    rm -rf "$stage"
fi
mkdir -p "$stage"
ditto "$project_root/build/Caffeine Modes.app" "$stage/Caffeine Modes.app"
ln -s /Applications "$stage/Applications"
if [[ -e "$dmg" ]]; then
    rm "$dmg"
fi
hdiutil create -quiet -volname "Caffeine Modes" -srcfolder "$stage" -ov -format UDZO "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"

xcrun notarytool submit "$dmg" \
    --keychain-profile "$profile" \
    --wait \
    --output-format json > "$project_root/dist/dmg-notarization-info.json"
rg -q '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$project_root/dist/dmg-notarization-info.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

printf 'PASS RELEASE %s\n' "$dmg"
