#!/bin/sh
R=/tmp/shairport
rm -f "$R/playing"
if [ -f "$R/restore-quasar" ]; then
  /data/shairport/ap2/quasar_start.sh && rm -f "$R/restore-quasar"
fi
exit 0
