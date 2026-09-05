#!/usr/bin/env bash
# Package the approved raster master without changing the artwork. macOS/sips.
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
signer_root="$project_root/apps/cold_signer"
icon_source="$project_root/branding/kt-cold-signer-logo-1024.png"
test -f "$icon_source"
mkdir -p "$signer_root/assets/brand"
sips -z 1024 1024 "$icon_source" --out "$signer_root/assets/brand/app_icon.png" >/dev/null
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%%:*}"
  pixels="${spec##*:}"
  sips -z "$pixels" "$pixels" "$icon_source" --out "$signer_root/android/app/src/main/res/mipmap-$density/ic_launcher.png" >/dev/null
done
for spec in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 29x29@3x:87 40x40@1x:40 40x40@2x:80 40x40@3x:120 60x60@2x:120 60x60@3x:180 76x76@1x:76 76x76@2x:152 83.5x83.5@2x:167 1024x1024@1x:1024; do
  icon_name="${spec%%:*}"
  pixels="${spec##*:}"
  sips -z "$pixels" "$pixels" "$icon_source" --out "$signer_root/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-$icon_name.png" >/dev/null
done
printf 'Updated cold signer Flutter, Android, and iOS icon assets.\n'
