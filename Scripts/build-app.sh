#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_name="Caffeine Modes"
bundle="$project_root/build/$app_name.app"
contents="$bundle/Contents"
identity="${CODE_SIGN_IDENTITY:--}"
app_version="${APP_VERSION:-1.0.1}"
build_number="${BUILD_NUMBER:-2}"

mkdir -p "$project_root/build" "$project_root/dist"
if [[ -e "$bundle" ]]; then
    rm -rf "$bundle"
fi

for architecture in arm64 x86_64; do
    swift build \
        --package-path "$project_root" \
        --configuration release \
        --product CaffeineModes \
        --arch "$architecture" \
        --scratch-path "$project_root/.build-$architecture"
done

arm_binary="$project_root/.build-arm64/arm64-apple-macosx/release/CaffeineModes"
intel_binary="$project_root/.build-x86_64/x86_64-apple-macosx/release/CaffeineModes"
test -x "$arm_binary"
test -x "$intel_binary"

mkdir -p "$contents/MacOS" "$contents/Resources"
lipo -create "$arm_binary" "$intel_binary" -output "$contents/MacOS/CaffeineModes"
cp "$project_root/Resources/Info.plist" "$contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$app_version" "$contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$contents/Info.plist"

"$project_root/Scripts/generate-icon.sh" >/dev/null
cp "$project_root/dist/AppIcon.icns" "$contents/Resources/AppIcon.icns"

sign_arguments=(--force --deep --options runtime --entitlements "$project_root/Resources/CaffeineModes.entitlements" --sign "$identity")
if [[ "$identity" != "-" ]]; then
    sign_arguments+=(--timestamp)
fi
codesign "${sign_arguments[@]}" "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"

printf 'PASS APP BUILD\n'
