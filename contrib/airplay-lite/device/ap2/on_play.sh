#!/bin/sh
R=/tmp/shairport
mkdir -p "$R"
touch "$R/playing"
# Stop the launcher first so that it cannot respawn the audio daemon.
for proc in /proc/[0-9]*; do
  if [ "$(readlink "$proc/exe" 2>/dev/null)" = /system/vendor/quasar/quasar_launcher2 ]; then
    touch "$R/restore-quasar"
    kill "${proc#/proc/}" 2>/dev/null
  fi
done
sleep 0.3
for proc in /proc/[0-9]*; do
  [ "$(readlink "$proc/exe" 2>/dev/null)" = /system/vendor/quasar/maind ] && kill "${proc#/proc/}" 2>/dev/null
done
sleep 0.5
for proc in /proc/[0-9]*; do
  case "$(readlink "$proc/exe" 2>/dev/null)" in
    /system/vendor/quasar/maind|/system/vendor/quasar/quasar_launcher2) kill -9 "${proc#/proc/}" 2>/dev/null ;;
  esac
done
exit 0
