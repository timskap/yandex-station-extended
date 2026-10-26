#!/bin/sh
D=/data/shairport
binary=$1
shift
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/shairport/bus
export ALSA_CONFIG_PATH=$D/etc/asound.conf
exec "$D/lib/ld-musl-aarch64.so.1" --library-path "$D/lib" "$D/bin/$binary" "$@"
