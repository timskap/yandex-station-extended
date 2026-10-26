#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
usage() {
  cat <<'EOF'
Установка AirPlay 2 на Станцию Лайт с CY8CMBR3108, ядро 4.9.68.
  install.sh --check SERIAL
  install.sh SERIAL MDNS_HOST [ARCHIVE]

Пример:
  install.sh 192.168.1.50:5555 yandexmicro-DEVICE_ID

MDNS_HOST — настоящее имя колонки из Bonjour, без .local.
Архив по умолчанию: ../packages/airplay-lite-5.6.2.tar.gz (+ .sha256).
Существующая установка не перезаписывается. --check не меняет файлы.
EOF
}
CHECK=0
case "${1:-}" in
  -h|--help|'') usage; exit 0 ;;
  --check) CHECK=1; shift ;;
esac
if [ "$CHECK" = 1 ]; then [ $# = 1 ] || { usage; exit 2; };
else [ $# -ge 2 ] && [ $# -le 3 ] || { usage; exit 2; }; fi
SERIAL=$1
ADB_BIN=${ADB_BIN:-adb}
adb_() { "$ADB_BIN" -s "$SERIAL" "$@"; }
command -v "$ADB_BIN" >/dev/null
if [[ "$SERIAL" == *:* ]]; then "$ADB_BIN" connect "$SERIAL" >/dev/null; fi
[ "$(adb_ get-state | tr -d '\r')" = device ] || { echo 'Устройство ADB недоступно.' >&2; exit 1; }
MODE=check
NEED_KB=32768
if [ "$CHECK" = 0 ]; then
  MODE=install
  command -v python3 >/dev/null
  ARCHIVE=${3:-$HERE/../packages/airplay-lite-5.6.2.tar.gz}
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  python3 "$HERE/bundle.py" unpack --archive "$ARCHIVE" --output "$TMP/package" --mdns-host "$2"
  NEED_KB=$(( $(du -sk "$TMP/package" | awk '{print $1}') + 4096 ))
fi
output=$(adb_ shell "sh -s $MODE $NEED_KB" < "$HERE/preflight.sh" | tr -d '\r')
printf '%s\n' "$output"
grep -qx AIRPLAY_PREFLIGHT_OK <<< "$output" || exit 1
[ "$CHECK" = 0 ] || exit 0
cp "$HERE/preflight.sh" "$HERE/install-device.sh" "$TMP/package/"
STAGE="/data/airplay-lite-install-$(date +%s)-$$"
adb_ push "$TMP/package" "$STAGE"
output=$(adb_ shell "sh $STAGE/install-device.sh $STAGE $NEED_KB" | tr -d '\r')
printf '%s\n' "$output"
if ! grep -qx AIRPLAY_INSTALL_OK <<< "$output"; then
  echo "Установка не завершена; файлы диагностики оставлены в $STAGE." >&2
  exit 1
fi
adb_ shell "rm -rf $STAGE"
echo 'Готово. Выберите Yandex Station Lite в списке AirPlay.'
