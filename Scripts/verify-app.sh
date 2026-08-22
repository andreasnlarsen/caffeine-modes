#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
bundle="${1:-$project_root/build/Caffeine Modes.app}"

if [[ $# -eq 0 ]]; then
    "$project_root/Scripts/build-app.sh" >/dev/null
fi
test -d "$bundle"

test -f "$bundle/Contents/Resources/Assets.car"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$bundle/Contents/Info.plist")" = "AppIcon"
asset_metadata="$(/usr/bin/assetutil -I "$bundle/Contents/Resources/Assets.car")"
[[ "$asset_metadata" == *'"PixelHeight" : 1024'* ]]

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "com.andreaslar.caffeinemodes"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$bundle/Contents/Info.plist")" = "true"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$bundle/Contents/Info.plist")"

architectures="$(lipo -archs "$bundle/Contents/MacOS/CaffeineModes")"
[[ "$architectures" == *arm64* ]]
[[ "$architectures" == *x86_64* ]]

codesign --verify --deep --strict "$bundle"
entitlements="$(codesign -d --entitlements :- "$bundle" 2>/dev/null | tr -d '[:space:]')"
[[ "$entitlements" == *'<key>com.apple.security.automation.apple-events</key><true/>'* ]]

printf 'PASS APP\n'
