#!/bin/sh
while sleep 5; do
  if ! /data/shairport/airplay.sh status >/dev/null 2>&1; then
    # Restore Alice even if the receiver crashes during playback.
    /data/shairport/ap2/on_stop.sh
    rm -f /tmp/shairport/monitor.pid
    /data/shairport/airplay.sh restart
    exit
  fi
done
