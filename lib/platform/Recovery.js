// Fixed detached cleanup template. All dynamic values are validated in QML and
// passed as positional arguments; none are interpolated into this program.
var cleanup = "set -eu\nstate=$1\nmonitors=$2\nsection=$3\nindex=$4\nrestore=$5\ndisplay_section=${6:-right}\ndisplay_index=${7:-0}\nrestore_display=${8:-0}\nworkspace_authority=${9:-}\ncolor_toggle=${10:-}\ncase \"$section\" in left|centerBegin|center|centerEnd|right|tray) ;; *) exit 2;; esac\ncase \"$index\" in ''|*[!0-9]*) exit 2;; esac\ncase \"$restore\" in 0|1) ;; *) exit 2;; esac\ncase \"$display_section\" in left|centerBegin|center|centerEnd|right|tray) ;; *) exit 2;; esac\ncase \"$display_index\" in ''|*[!0-9]*) exit 2;; esac\ncase \"$restore_display\" in 0|1) ;; *) exit 2;; esac\nsleep 3\nready=0\nfor attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do\n  if omarchy-shell shell ping >/dev/null 2>&1; then ready=1; break; fi\n  sleep 1\ndone\n[ \"$ready\" = 1 ] || exit 0\nplugins=$(omarchy-shell shell listPlugins) || exit 0\nprintf '%s' \"$plugins\" | jq -e 'type == \"array\"' >/dev/null || exit 0\nif printf '%s' \"$plugins\" | jq -e 'any(.[]; .id == \"yakumy.station\" and .enabled == true)' >/dev/null; then exit 0; fi\nif [ \"$restore\" = 1 ]; then\n  omarchy plugin enable omarchy.workspaces >/dev/null\n  omarchy bar move omarchy.workspaces --section \"$section\" --index \"$index\" >/dev/null\nfi\nif [ \"$restore_display\" = 1 ]; then\n  omarchy plugin enable omarchy.monitor >/dev/null\n  omarchy bar move omarchy.monitor --section \"$display_section\" --index \"$display_index\" >/dev/null\nfi\nplain=$state/monitors-block.plain.lua\nif [ -f \"$monitors\" ] && [ ! -L \"$monitors\" ]; then\n  if awk '/^-- >>> station \\(managed; edited by the Station panel\\) >>>$/ {start++} /^-- <<< station <<<$/{end++} END{exit !(start==1 && end==1)}' \"$monitors\"; then\n    temporary=$(mktemp \"${monitors}.station.XXXXXX\")\n    trap 'rm -f \"$temporary\"' EXIT HUP INT TERM\n    cp -p -- \"$monitors\" \"${monitors}.bak.station.$(date +%s)\"\n    awk '\n      /^-- >>> station \\(managed; edited by the Station panel\\) >>>$/ {inside=1; print; next}\n      /^-- <<< station <<<$/{inside=0; print; next}\n      inside && /^[[:space:]]*hl\\.monitor\\(/ {\n        gsub(/disabled = true/, \"disabled = false\")\n        gsub(/mirror = \"[A-Za-z0-9_.:-]*\"/, \"mirror = \\\"\\\"\")\n      }\n      {print}\n    ' \"$monitors\" > \"$temporary\"\n    chmod --reference=\"$monitors\" \"$temporary\"\n    mv -- \"$temporary\" \"$monitors\"\n    trap - EXIT HUP INT TERM\n  fi\nfi\nstate_file=$state/state.json\nif [ -f \"$state_file\" ] && [ ! -L \"$state_file\" ]; then\n  state_tmp=$(mktemp \"${state_file}.cleanup.XXXXXX\")\n  if jq '.stockLease = null | .displayLease = null | .appliedBinds = []' \"$state_file\" > \"$state_tmp\"; then\n    chmod --reference=\"$state_file\" \"$state_tmp\"\n    mv -- \"$state_tmp\" \"$state_file\"\n  else\n    rm -f -- \"$state_tmp\"\n  fi\nfi\n[ -z \"$workspace_authority\" ] || rm -f -- \"$workspace_authority\"\n[ -z \"$color_toggle\" ] || rm -f -- \"$color_toggle\"\nhyprctl reload >/dev/null\n"

function validLease(lease, section) {
  var fallback = { section: section, index: 0, wasEnabled: false, disabledByStation: false }
  if (!lease || ["left", "centerBegin", "center", "centerEnd", "right", "tray"].indexOf(lease.section) === -1
      || !Number.isInteger(lease.index) || lease.index < 0) return fallback
  return lease
}

function restoreFlag(lease) { return lease.disabledByStation && lease.wasEnabled ? "1" : "0" }

// Argv for the detached cleanup. Malformed leases restore nothing.
function cleanupCommand(stateDir, monitorsPath, stockLease, displayLease, workspaceAuthorityPath, colorTogglePath) {
  var stock = validLease(stockLease, "left"), display = validLease(displayLease, "right")
  var argv = ["sh", "-c", cleanup, "sh", stateDir, monitorsPath,
    stock.section, String(stock.index), restoreFlag(stock),
    display.section, String(display.index), restoreFlag(display)]
  if (workspaceAuthorityPath) argv.push(String(workspaceAuthorityPath))
  // Removing Color Match's file before the reload returns every output to its own colors.
  if (workspaceAuthorityPath && colorTogglePath) argv.push(String(colorTogglePath))
  return argv
}

if (typeof module !== "undefined") module.exports = { cleanup: cleanup, cleanupCommand: cleanupCommand }
