#!/bin/sh
set -eu
D=/data/shairport
R=/tmp/shairport
live() {
  [ -s "$R/$1.pid" ] || return 1
  pid=$(cat "$R/$1.pid")
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  tr '\000' '\n' < "/proc/$pid/cmdline" | grep -q -F "$D/"
}
launch() {
  name=$1
  shift
  live "$name" && return 0
  setsid "$D/run.sh" "$name" "$@" > "$R/$name.log" 2>&1 </dev/null &
  echo $! > "$R/$name.pid"
  sleep 1
  live "$name" || { cat "$R/$name.log"; return 1; }
}
stop() {
  for name in monitor airplay-buttons shairport-sync nqptp avahi-daemon dbus-daemon; do
    if live "$name"; then
      pid=$(cat "$R/$name.pid")
      kill "$pid" 2>/dev/null || true
      tries=0
      while kill -0 "$pid" 2>/dev/null && [ "$tries" -lt 20 ]; do
        sleep 0.1
        tries=$((tries + 1))
      done
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$R/$name.pid"
  done
  "$D/ap2/on_stop.sh"
  rm -f "$R/bus"
}
start() {
  mkdir -p "$R" /run/avahi-daemon
  chmod 700 "$R"
  launch dbus-daemon --config-file="$D/etc/airplay-bus.conf" --nofork || return 1
  launch avahi-daemon --no-drop-root --no-chroot --no-rlimits --no-proc-title -f "$D/etc/avahi-daemon.conf" || return 1
  launch nqptp || return 1
  launch shairport-sync -c "$D/ap2/shairport.conf" || return 1
  launch airplay-buttons || return 1
  if ! live monitor; then
    setsid "$D/monitor.sh" > "$R/monitor.log" 2>&1 </dev/null &
    echo $! > "$R/monitor.pid"
  fi
}
status() {
  result=0
  for name in dbus-daemon avahi-daemon nqptp shairport-sync airplay-buttons monitor; do
    if live "$name"; then echo "$name: running (pid $(cat "$R/$name.pid"))";
    else echo "$name: stopped"; result=1; fi
  done
  return "$result"
}
case "${1:-status}" in
  start) start || { stop; exit 1; }; status ;;
  stop) stop ;;
  restart) stop; start || { stop; exit 1; }; status ;;
  status) status ;;
  *) echo 'Usage: airplay.sh start|stop|restart|status'; exit 2 ;;
esac
