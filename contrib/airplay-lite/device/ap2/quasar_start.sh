#!/bin/sh
for proc in /proc/[0-9]*; do
  [ "$(readlink "$proc/exe" 2>/dev/null)" = /system/vendor/quasar/quasar_launcher2 ] && exit 0
done
echo 1 > /proc/sys/vm/overcommit_memory
ulimit -n 10240
ulimit -s 1024
unset ALSA_CONFIG_PATH DBUS_SYSTEM_BUS_ADDRESS
export PATH=/system/vendor/quasar:/usr/sbin:/usr/bin:/sbin:/bin
export GST_PLUGIN_PATH=/system/vendor/quasar/libs
export LD_LIBRARY_PATH=/system/vendor/quasar:/system/vendor/quasar/libs
export CA_CERTIFICATES=/system/vendor/quasar/ca-certificates.crt
cd /data/quasar || exit 1
setsid /system/vendor/quasar/quasar_launcher2 /system/vendor/quasar/launch.json > launcher2.out 2>&1 </dev/null &
