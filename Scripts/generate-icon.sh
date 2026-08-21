#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
output_dir="$project_root/dist"
iconset="$output_dir/AppIcon.iconset"

mkdir -p "$output_dir" "$iconset"
xcrun swift "$project_root/Scripts/generate-icon.swift" "$output_dir/AppIcon-1024.png"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$output_dir/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" "$output_dir/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$output_dir/AppIcon.icns"
printf 'PASS ICON\n'
