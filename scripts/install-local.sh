#!/bin/bash
# Release ビルド → 旧アプリを /tmp に退避 → 安定した自己署名 ID で署名 → /Applications に入れて起動。
# ad-hoc 署名はビルドごとに cdhash が変わり、macOS の許可 (キーチェーン/TCC) が引き継がれないため。
# Kimi Vivace のクラウド取得先は project.yml の USAGEDOCK_CLOUD_HOST（ホスト名だけ）。
# このビルドだけ変えるとき: USAGEDOCK_CLOUD_HOST=<host> scripts/install-local.sh
set -euo pipefail
IDENTITY="${USAGEDOCK_SIGNING_IDENTITY:-Board-Man Local Developer}"
DD=/tmp/ud-build
APP="$DD/Build/Products/Release/UsageDock.app"
cd "$(dirname "$0")/.."
xcodebuild -scheme UsageDock -configuration Release -derivedDataPath "$DD" ${USAGEDOCK_CLOUD_HOST:+"USAGEDOCK_CLOUD_HOST=$USAGEDOCK_CLOUD_HOST"} build | tail -1
# 取得先がアプリに入っていなければ、今のアプリを置き換えずに止める（入れるとクラウドの Kimi が「クラウド未取得」のままになる）。
CLOUD_HOST=$(/usr/libexec/PlistBuddy -c 'Print :UsageDockCloudHost' "$APP/Contents/Info.plist" 2>/dev/null || true)
HOST_RE='^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'
if ! [[ $CLOUD_HOST =~ $HOST_RE ]]; then
  echo "ERROR: UsageDockCloudHost がビルドに入っていません（USAGEDOCK_CLOUD_HOST を確認）。/Applications のアプリはそのままです" >&2
  exit 1
fi
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
