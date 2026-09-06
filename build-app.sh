#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
output_dir="${1:-$project_dir/dist}"
mkdir -p "$output_dir"
output_dir="${output_dir:A}"
app_dir="$output_dir/NeoKeys.app"

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp ".build/release/NeoKeys" "$app_dir/Contents/MacOS/NeoKeys"
cp "$project_dir/Resources/NeoKeys.icns" "$app_dir/Contents/Resources/NeoKeys.icns"
cp -R "$project_dir/Resources/Sounds" "$app_dir/Contents/Resources/Sounds"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>pt</string>
    <key>CFBundleDisplayName</key><string>NeoKeys</string>
    <key>CFBundleExecutable</key><string>NeoKeys</string>
    <key>CFBundleIconFile</key><string>NeoKeys.icns</string>
    <key>CFBundleGetInfoString</key><string>NeoKeys — sons de teclado exclusivamente para MacBook Neo</string>
    <key>CFBundleIdentifier</key><string>pt.arqueox.neokeys</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>NeoKeys</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4</string>
    <key>CFBundleVersion</key><string>5</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 arqueox</string>
</dict>
</plist>
PLIST

xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
