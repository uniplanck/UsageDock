#!/bin/bash
# Release ビルド → 旧アプリを /tmp に退避 → 安定した自己署名 ID で署名 → /Applications に入れて起動。
# ad-hoc 署名はビルドごとに cdhash が変わり、macOS の許可 (キーチェーン/TCC) が引き継がれないため。
set -euo pipefail
IDENTITY="${USAGEDOCK_SIGNING_IDENTITY:-Board-Man Local Developer}"
DD=/tmp/ud-build
APP="$DD/Build/Products/Release/UsageDock.app"
cd "$(dirname "$0")/.."
xcodebuild -scheme UsageDock -configuration Release -derivedDataPath "$DD" build | tail -1
if [ -d /Applications/UsageDock.app ]; then cp -R /Applications/UsageDock.app "/tmp/UsageDock-backup-$(date +%Y%m%d-%H%M%S).app"; fi
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$IDENTITY\""; then
  ENT=$(mktemp); codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null || true
  if [ -s "$ENT" ]; then codesign --force --deep --timestamp=none --entitlements "$ENT" --sign "$IDENTITY" "$APP"
  else codesign --force --deep --timestamp=none --sign "$IDENTITY" "$APP"; fi
  rm -f "$ENT"
else
  echo "WARN: signing identity '$IDENTITY' not found; keeping ad-hoc signature" >&2
fi
codesign --verify --deep --strict "$APP"
osascript -e 'quit app "UsageDock"' >/dev/null 2>&1 || true; sleep 2; pkill -x UsageDock || true
rm -rf /Applications/UsageDock.app && cp -R "$APP" /Applications/ && open /Applications/UsageDock.app
codesign -dr - /Applications/UsageDock.app 2>&1 | tail -1
