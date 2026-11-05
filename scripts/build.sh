#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-engine.sh
swift build -c release --arch arm64 -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/MoleDPI"
APP="dist/MoleDPI.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/MoleDPI.icns "$APP/Contents/Resources/"
cp .build/native/moledpi-service .build/native/tpws .build/native/moledpi-pf "$APP/Contents/Resources/"
for executable in tpws moledpi-pf moledpi-service; do strip -S -x "$APP/Contents/Resources/$executable"; done
codesign --force --options runtime --sign - "$APP/Contents/Resources/tpws"
codesign --force --options runtime --sign - "$APP/Contents/Resources/moledpi-pf"
codesign --force --options runtime --sign - "$APP/Contents/Resources/moledpi-service"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$BIN_DIR/MoleDPI" "$APP/Contents/MacOS/"
strip -S -x "$APP/Contents/MacOS/MoleDPI"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MoleDPI</string>
<key>CFBundleIdentifier</key><string>local.moledpi.app</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleIconFile</key><string>MoleDPI.icns</string>
<key>CFBundleVersion</key><string>93</string>
<key>CFBundleName</key><string>MoleDPI</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.9.3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
for name in moledpi-service moledpi-pf tpws; do
  digest=$(shasum -a 256 "$APP/Contents/Resources/$name" | cut -d' ' -f1)
  /usr/libexec/PlistBuddy -c "Add :MoleSHA-$name string $digest" "$APP/Contents/Info.plist"
done
digest=$(codesign -dvvv "$APP/Contents/Resources/moledpi-service" 2>&1 | sed -n 's/^CDHash=//p')
[[ ${#digest} == 40 ]]
/usr/libexec/PlistBuddy -c "Add :MoleServiceCDHash string $digest" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Licenses"
cp vendor/zapret/tpws/epoll-shim/LICENSE "$APP/Contents/Resources/Licenses/epoll-shim-MIT.txt"
cp LICENSE NOTICE THIRD-PARTY.md "$APP/Contents/Resources/Licenses/"
cp vendor/zapret/LICENSE.txt "$APP/Contents/Resources/Licenses/Zapret-MIT.txt"
# Ship complete corresponding source and all embedded dependency notices.
SOURCE_DIR="$APP/Contents/Resources/Source"
mkdir -p "$SOURCE_DIR"
cp -R Sources Native vendor scripts Checks Tests Resources "$SOURCE_DIR/"
cp README.md BUILDING.md RELEASE-NOTES.md SECURITY.md Package.swift LICENSE NOTICE THIRD-PARTY.md "$SOURCE_DIR/"
codesign --force --options runtime --sign - "$APP"
printf 'Hazır: %s/dist/MoleDPI.app\n' "$PWD"
