# Fixed detached M0 cleanup template. Arguments are supplied by the fixture.
set -eu
state=$1
monitors=$2
section=$3
index=$4
restore=$5
case "$section" in left|center|right) ;; *) exit 2;; esac
case "$index" in ''|*[!0-9]*) exit 2;; esac
case "$restore" in 0|1) ;; *) exit 2;; esac
sleep 3
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if omarchy-shell shell ping >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || exit 0
plugins=$(omarchy-shell shell listPlugins) || exit 0
printf '%s' "$plugins" | jq -e 'type == "array"' >/dev/null || exit 0
if printf '%s' "$plugins" | jq -e 'any(.[]; .id == "yakumy.station-m0" and .enabled == true)' >/dev/null; then
  printf '%s restart-skip\n' "$(date +%s.%N)" >> "$state/lifecycle.log"
  exit 0
fi
if [ "$restore" = 1 ]; then
  omarchy plugin enable omarchy.workspaces >/dev/null
  omarchy bar move omarchy.workspaces --section "$section" --index "$index" >/dev/null
fi
plain=$state/monitors-block.plain.lua
if [ -f "$monitors" ] && [ ! -L "$monitors" ] && [ -f "$plain" ] && [ ! -L "$plain" ]; then
  if awk '/^-- >>> station-m0 >>>$/ {start++} /^-- <<< station-m0 <<<$/{end++} END{exit !(start==1 && end==1)}' "$monitors"; then
    temporary=$(mktemp "${monitors}.m0.XXXXXX")
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    cp -p -- "$monitors" "${monitors}.bak.m0.$(date +%s)"
    awk -v plain="$plain" '
      /^-- >>> station-m0 >>>$/ {print; while ((getline line < plain)>0) print line; close(plain); inside=1; next}
      /^-- <<< station-m0 <<<$/{inside=0; print; next}
      !inside {print}
    ' "$monitors" > "$temporary"
    chmod --reference="$monitors" "$temporary"
    mv -- "$temporary" "$monitors"
    trap - EXIT HUP INT TERM
  fi
fi
hyprctl reload >/dev/null
printf '%s cleanup-reloaded\n' "$(date +%s.%N)" >> "$state/lifecycle.log"
