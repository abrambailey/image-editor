#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/module-cache .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
./scripts/prepare-model.sh
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" \
    --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
app="$PWD/dist/Image Editor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Replace the executable atomically so a running editor keeps its mapped binary
# and unsaved canvas while a new build is packaged.
cp .build/release/ImageEditor "$app/Contents/MacOS/ImageEditor.next"
mv -f "$app/Contents/MacOS/ImageEditor.next" "$app/Contents/MacOS/ImageEditor"
cp Resources/Info.plist "$app/Contents/Info.plist"
rm -rf "$app/Contents/Resources/BiRefNetLite.mlmodelc"
cp -R .build/models/BiRefNetLite.mlmodelc "$app/Contents/Resources/"
cp -R Resources/ThirdParty "$app/Contents/Resources/"
cp LICENSE "$app/Contents/Resources/LICENSE"
if [[ ! -f "$app/Contents/Resources/AppIcon.icns" || scripts/make-icon.swift -nt "$app/Contents/Resources/AppIcon.icns" ]]; then
    swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
    iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$app"
echo "Built: $app"
