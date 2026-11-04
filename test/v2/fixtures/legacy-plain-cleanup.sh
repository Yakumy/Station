# Historical Station cleanup fixture. Do not execute against a live desktop.
# Source revision: 86f6cf4bc488e5217af2a0a8fe72673b528a4e6b
# Source path: lib/Recovery.js cleanup (before v3 authority revision).
set -eu
state=$1
monitors=$2
section=$3
index=$4
restore=$5
display_section=${6:-right}
display_index=${7:-0}
restore_display=${8:-0}
case "$section" in left|center|right) ;; *) exit 2;; esac
case "$index" in ''|*[!0-9]*) exit 2;; esac
case "$restore" in 0|1) ;; *) exit 2;; esac
case "$display_section" in left|center|right) ;; *) exit 2;; esac
case "$display_index" in ''|*[!0-9]*) exit 2;; esac
case "$restore_display" in 0|1) ;; *) exit 2;; esac
sleep 3
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if omarchy-shell shell ping >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || exit 0
plugins=$(omarchy-shell shell listPlugins) || exit 0
printf '%s' "$plugins" | jq -e 'type == "array"' >/dev/null || exit 0
if printf '%s' "$plugins" | jq -e 'any(.[]; .id == "yakumy.station" and .enabled == true)' >/dev/null; then exit 0; fi
if [ "$restore" = 1 ]; then
  omarchy plugin enable omarchy.workspaces >/dev/null
  omarchy bar move omarchy.workspaces --section "$section" --index "$index" >/dev/null
fi
if [ "$restore_display" = 1 ]; then
  omarchy plugin enable omarchy.monitor >/dev/null
  omarchy bar move omarchy.monitor --section "$display_section" --index "$display_index" >/dev/null
fi
plain=$state/monitors-block.plain.lua
if [ -f "$monitors" ] && [ ! -L "$monitors" ] && [ -f "$plain" ] && [ ! -L "$plain" ]; then
  if awk '/^-- >>> station \(managed; edited by the Station panel\) >>>$/ {start++} /^-- <<< station <<<$/{end++} END{exit !(start==1 && end==1)}' "$monitors"; then
    temporary=$(mktemp "${monitors}.station.XXXXXX")
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    cp -p -- "$monitors" "${monitors}.bak.station.$(date +%s)"
    awk -v plain="$plain" '
      /^-- >>> station \(managed; edited by the Station panel\) >>>$/ {print; while ((getline line < plain)>0) print line; close(plain); inside=1; next}
      /^-- <<< station <<<$/{inside=0; print; next}
      !inside {print}
    ' "$monitors" > "$temporary"
    chmod --reference="$monitors" "$temporary"
    mv -- "$temporary" "$monitors"
    trap - EXIT HUP INT TERM
  fi
fi
state_file=$state/state.json
if [ -f "$state_file" ] && [ ! -L "$state_file" ]; then
  state_tmp=$(mktemp "${state_file}.cleanup.XXXXXX")
  if jq '.stockLease = null | .displayLease = null | .appliedBinds = []' "$state_file" > "$state_tmp"; then
    chmod --reference="$state_file" "$state_tmp"
    mv -- "$state_tmp" "$state_file"
  else
    rm -f -- "$state_tmp"
  fi
fi
hyprctl reload >/dev/null
