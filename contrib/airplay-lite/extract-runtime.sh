#!/bin/sh
set -eu
mkdir -p /out/runtime/bin /out/runtime/lib
: > /tmp/airplay-libraries
for binary in /usr/local/bin/shairport-sync /usr/local/bin/nqptp /usr/sbin/avahi-daemon /usr/bin/dbus-daemon; do
  cp "$binary" /out/runtime/bin/
  ldd "$binary" >> /tmp/airplay-libraries
done
awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}' /tmp/airplay-libraries | sort -u | while read -r library; do
  test -f "$library"
  cp -L "$library" /out/runtime/lib/
done
cp -L /lib/ld-musl-aarch64.so.1 /out/runtime/lib/
/usr/local/bin/shairport-sync -V
/usr/local/bin/nqptp -V
