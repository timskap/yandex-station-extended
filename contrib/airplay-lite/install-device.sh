#!/bin/sh
set -eu
STAGE=$1
NEED_KB=$2
case "$STAGE" in /data/airplay-lite-install-[0-9]*-[0-9]*) ;; *) exit 2 ;; esac
sh "$STAGE/preflight.sh" install "$NEED_KB"
(cd "$STAGE/shairport" && sha256sum -c MANIFEST.sha256) >/dev/null
D=/data/shairport
mv "$STAGE/shairport" "$D"
mkdir -p "$D/backup"
chmod 700 "$D/backup"
cp -p /etc/passwd "$D/backup/passwd.before-airplay"
cp -p /etc/group "$D/backup/group.before-airplay"
ROOT_REMOUNTED=0
cleanup() {
  sync
  if [ "$ROOT_REMOUNTED" = 1 ]; then mount -o remount,ro /; fi
}
trap cleanup EXIT
if awk '$2 == "/" && $4 ~ /(^|,)ro(,|$)/ {found=1} END {exit !found}' /proc/mounts; then
  mount -o remount,rw /
  ROOT_REMOUNTED=1
fi
if ! grep -q '^avahi:' /etc/passwd; then
  printf 'avahi:x:86:\n' >> /etc/group
  printf 'avahi:x:86:86:Avahi:/:/bin/false\n' >> /etc/passwd
  touch "$D/backup/avahi-account-created"
fi
cp "$STAGE/S99zairplay" /etc/init.d/S99zairplay
chmod 755 /etc/init.d/S99zairplay "$D"/*.sh "$D"/ap2/*.sh "$D"/bin/* "$D"/lib/*
sync
if [ "$ROOT_REMOUNTED" = 1 ]; then
  mount -o remount,ro /
  ROOT_REMOUNTED=0
fi
if ! "$D/airplay.sh" start; then
  echo 'AirPlay не запустился. Файлы оставлены для диагностики; логи: /tmp/shairport/.'
  exit 1
fi
echo AIRPLAY_INSTALL_OK
