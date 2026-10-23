#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build dist
python3 scripts/prepare_dependencies.py
swift scripts/make_icon.swift PyLearn/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
xcodegen generate
xcodebuild -project PyLearn.xcodeproj -scheme PyLearn -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build/device \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > .build/device-build.log 2>&1 || { tail -100 .build/device-build.log; exit 1; }
APP="$PWD/.build/device/Build/Products/Release-iphoneos/PyLearn.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
while IFS= read -r -d '' framework; do
  codesign --force --sign - --timestamp=none "$framework"
done < <(find "$APP/Frameworks" -depth -type d -name '*.framework' -print0)
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/PyLearn.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Payload" "dist/PyLearn-$VERSION.ipa"
python3 scripts/inspect_ipa.py "dist/PyLearn-$VERSION.ipa" | tee dist/verification.json
shasum -a 256 "dist/PyLearn-$VERSION.ipa" > dist/SHA256SUMS.txt
