#!/bin/zsh
set -eu
cd "${0:A:h}"
swift build -c release "$@"
APP="$PWD/dist/AI Quota.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AIQuota "$APP/Contents/MacOS/AIQuota"
cp -R .build/release/AIQuota_QuotaCore.bundle "$APP/Contents/Resources/"
cp -R Assets/WatchCats "$APP/Contents/Resources/"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
