#!/bin/sh
set -eu
case "${1:-}" in
  1|2) value=$1 ;;
  *) exit 2 ;;
esac
pressed_ms=$(date +%s%3N)
exec omarchy-shell yakumy.station-m0 switchTimed "$value" "$pressed_ms"
