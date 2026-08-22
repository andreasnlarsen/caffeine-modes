#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
bundle="${1:-$project_root/build/Caffeine Modes.app}"

if [[ $# -eq 0 ]]; then
    "$project_root/Scripts/build-app.sh" >/dev/null
fi
test -d "$bundle"

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
