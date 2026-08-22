#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
output_dir="$project_root/dist"
asset_catalog="$output_dir/AppIcon.xcassets"
iconset="$asset_catalog/AppIcon.appiconset"
compiled_assets="$output_dir/AppIcon.compiled"

mkdir -p "$iconset" "$compiled_assets"
cp "$project_root/Resources/AppIcon.xcassets/Contents.json" "$asset_catalog/Contents.json"
cp "$project_root/Resources/AppIcon.xcassets/AppIcon.appiconset/Contents.json" "$iconset/Contents.json"
xcrun swift "$project_root/Scripts/generate-icon.swift" "$output_dir/AppIcon-1024.png"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$output_dir/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" "$output_dir/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

xcrun actool "$asset_catalog" \
    --compile "$compiled_assets" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$output_dir/AppIcon-info.plist" \
    >/dev/null
cp "$compiled_assets/AppIcon.icns" "$output_dir/AppIcon.icns"
printf 'PASS ICON\n'
