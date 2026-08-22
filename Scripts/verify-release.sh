#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
version="${APP_VERSION:-1.0.1}"
dmg="${1:-$project_root/dist/Caffeine-Modes-$version.dmg}"
mount_point=""

cleanup() {
    if [[ -n "$mount_point" ]]; then
        hdiutil detach -quiet "$mount_point" || true
    fi
}
trap cleanup EXIT

test -f "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

attach_output="$(hdiutil attach -readonly -nobrowse -plist "$dmg")"
mount_point="$(print -r -- "$attach_output" | plutil -extract system-entities xml1 -o - - | rg -o '<string>/Volumes/[^<]+' | sed 's/<string>//' | tail -1)"
test -n "$mount_point"
bundle="$mount_point/Caffeine Modes.app"
test -d "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"
entitlements="$(codesign -d --entitlements :- "$bundle" 2>/dev/null | tr -d '[:space:]')"
[[ "$entitlements" == *'<key>com.apple.security.automation.apple-events</key><true/>'* ]]
xcrun stapler validate "$bundle"
spctl --assess --type execute --verbose=2 "$bundle"

architectures="$(lipo -archs "$bundle/Contents/MacOS/CaffeineModes")"
[[ "$architectures" == *arm64* ]]
[[ "$architectures" == *x86_64* ]]
team="$(codesign -dv --verbose=4 "$bundle" 2>&1 | awk -F= '/^TeamIdentifier=/ {print $2}')"
test "$team" = "D79LWN85PJ"

printf 'PASS RELEASE VERIFIED\n'
