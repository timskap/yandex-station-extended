#!/bin/sh
# Read-only checks; also run on the device immediately before installation.
set -eu
MODE=${1:-check}
NEED_KB=${2:-32768}
die() { echo "ОШИБКА: $*"; exit 1; }
[ "$(id -u)" = 0 ] || die 'Нужен root по ADB.'
tr '\000' '\n' < /proc/device-tree/compatible | grep -qx 'yandex,station-micro' || die 'Пакет проверен только на Станции Лайт (station-micro).'
[ "$(uname -m)" = aarch64 ] || die 'Нужно ядро aarch64.'
[ "$(uname -r)" = 4.9.68 ] || die 'Проверена только версия ядра 4.9.68.'
[ "$(cat /sys/class/input/event1/device/name)" = cy8cmbr3108 ] || die 'Проверены кнопки CY8CMBR3108 на event1; другая ревизия требует проверки.'
[ -e /dev/snd/pcmC0D0p ] || die 'Нет ожидаемого звукового устройства.'
[ -d /sys/class/leds/micro:blue:ring1 ] || die 'Нет ожидаемого LED-кольца.'
for command in setsid sha256sum readlink amixer aplay dbus-send; do
  command -v "$command" >/dev/null || die "Нет команды $command."
done
echo "Модель: station-micro; ядро: $(uname -r); кнопки: CY8CMBR3108."
df -h /data
if [ "$MODE" = install ]; then
  [ ! -e /data/shairport ] || die '/data/shairport уже существует; рабочая установка не перезаписывается.'
  [ ! -e /etc/init.d/S99zairplay ] || die 'S99zairplay уже существует.'
  available=$(df -k /data | awk 'END {print $4}')
  [ "$available" -ge "$NEED_KB" ] || die "Нужно минимум $NEED_KB КБ свободного места."
  if grep -q '^avahi:' /etc/passwd || grep -q '^avahi:' /etc/group; then
    grep -q '^avahi:' /etc/passwd && grep -q '^avahi:' /etc/group || die 'Учётная запись/группа avahi созданы не полностью.'
  else
    if awk -F: '$3 == 86 {found=1} END {exit !found}' /etc/passwd /etc/group; then
      die 'UID/GID 86 занят; его нельзя использовать для avahi.'
    fi
  fi
elif [ -x /data/shairport/airplay.sh ]; then
  /data/shairport/airplay.sh status || true
fi
echo AIRPLAY_PREFLIGHT_OK
