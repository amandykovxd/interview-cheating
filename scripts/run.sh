#!/usr/bin/env bash
#
# Сборка приложения в стабильный .app и запуск.
#
# Зачем: при `swift run` бинарь неподписан, и macOS TCC при каждой пересборке
# видит новый код -> заново просит разрешения (микрофон, запись экрана,
# accessibility). Мы подписываем .app ПОСТОЯННЫМ self-signed сертификатом.
# Тогда TCC ключует разрешения по подписи, и после первого раза модалка
# больше не появляется — пересборки её не сбрасывают.
#
# Использование: ./scripts/run.sh [debug|release]

set -euo pipefail

APP_NAME="Assistant"
BUNDLE_ID="com.assistant.app"
IDENTITY="Assistant Dev"
CONFIG="${1:-debug}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/$APP_NAME.app"

# --- 1. Постоянный сертификат для подписи (создаём один раз) ---
ensure_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
        return
    fi
    echo ">> Создаю self-signed сертификат '$IDENTITY' (один раз)..."
    local tmp; tmp="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
        -subj "/CN=$IDENTITY" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
    openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -out "$tmp/id.p12" -passout pass:assistant -name "$IDENTITY" >/dev/null 2>&1
    security import "$tmp/id.p12" \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        -P assistant -T /usr/bin/codesign >/dev/null 2>&1
    rm -rf "$tmp"
    echo ">> Сертификат создан. При первой подписи macOS может спросить доступ"
    echo "   к ключу — нажмите 'Always Allow', чтобы больше не спрашивал."
}

ensure_identity

# --- 2. Сборка ---
echo ">> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

# --- 3. Сборка бандла .app ---
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# --- 4. Подпись постоянной идентичностью ---
# identifier фиксируем, чтобы designated requirement не менялся между сборками
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"

# --- 5. Перезапуск ---
killall "$APP_NAME" 2>/dev/null || true
sleep 0.3
open "$APP"
echo ">> Запущено: $APP"
echo "   Значок 'AI' в menu bar. Выход: AI -> Выход."
