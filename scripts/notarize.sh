#!/usr/bin/env bash
#
# Сборка релизного .app, подпись Developer ID, нотаризация и стейплинг.
#
# ВАЖНО: для этого нужен платный Apple Developer аккаунт и Developer ID Application
# сертификат в keychain. Дев-скрипт scripts/run.sh использует self-signed подпись
# только для локального запуска — раздавать так нельзя (Gatekeeper заблокирует).
#
# Что нужно один раз:
#   1. Apple Developer Program ($99/год).
#   2. Сертификат "Developer ID Application: <Имя> (TEAMID)" в login keychain
#      (Xcode -> Settings -> Accounts -> Manage Certificates, или developer.apple.com).
#   3. App-specific password для нотаризации, сохранённый в keychain-профиль:
#        xcrun notarytool store-credentials "assistant-notary" \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-spec-pass"
#
# Использование:
#   IDENTITY="Developer ID Application: Имя (TEAMID)" \
#   KEYCHAIN_PROFILE="assistant-notary" \
#   ./scripts/notarize.sh

set -euo pipefail

APP_NAME="Assistant"
BUNDLE_ID="com.assistant.app"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME.dmg"

: "${IDENTITY:?нужен IDENTITY (Developer ID Application: ...)}"
: "${KEYCHAIN_PROFILE:?нужен KEYCHAIN_PROFILE (см. notarytool store-credentials)}"

# --- 1. Release-сборка ---
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

# --- 2. Сборка бандла ---
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/WhisperWorker" "$APP/Contents/MacOS/WhisperWorker"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# --- 3. Подпись с hardened runtime ---
# Нотаризация требует hardened runtime (--options runtime). Вложенный worker и
# ресурсы подписываем изнутри наружу.
ENTITLEMENTS="$ROOT/Resources/Assistant.entitlements"
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP/Contents/MacOS/WhisperWorker"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"

echo ">> проверка подписи"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- 4. Упаковка в DMG ---
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG"

# --- 5. Нотаризация и стейплинг ---
echo ">> отправка на нотаризацию (может занять пару минут)"
xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

echo ">> готово: $DMG нотаризован и застейплен"
