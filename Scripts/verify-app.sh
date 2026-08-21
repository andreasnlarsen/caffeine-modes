#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
bundle="${1:-$project_root/build/Caffeine Modes.app}"

if [[ ! -d "$bundle" ]]; then
    "$project_root/Scripts/build-app.sh" >/dev/null
fi

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "com.andreaslar.caffeinemodes"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$bundle/Contents/Info.plist")" = "true"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$bundle/Contents/Info.plist")"

architectures="$(lipo -archs "$bundle/Contents/MacOS/CaffeineModes")"
[[ "$architectures" == *arm64* ]]
[[ "$architectures" == *x86_64* ]]

codesign --verify --deep --strict "$bundle"
entitlements="$(codesign -d --entitlements :- "$bundle" 2>/dev/null)"
[[ "$entitlements" == *com.apple.security.automation.apple-events* ]]

printf 'PASS APP\n'
