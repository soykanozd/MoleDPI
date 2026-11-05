#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto dist/MoleDPI.app "$stage/MoleDPI.app"
ln -s /Applications "$stage/Applications"
tool="$stage/Uninstall MoleDPI.app/Contents"
mkdir -p "$tool/MacOS"
swiftc -parse-as-library -target arm64-apple-macos13.0 Native/Uninstall.swift -o "$tool/MacOS/Uninstall"
cat > "$tool/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Uninstall</string>
<key>CFBundleIdentifier</key><string>local.moledpi.uninstall</string>
<key>CFBundleName</key><string>Uninstall MoleDPI</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
strip -S -x "$tool/MacOS/Uninstall"
codesign --force --options runtime --sign - "$stage/Uninstall MoleDPI.app"
cp README.md "$stage/Read Me.md"
hdiutil create -quiet -ov -volname MoleDPI -srcfolder "$stage" -format UDZO dist/MoleDPI.dmg
hdiutil verify dist/MoleDPI.dmg
shasum -a 256 dist/MoleDPI.dmg > dist/SHA256SUMS
