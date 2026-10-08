// Fixed transaction template. Candidate files are written inside Station's
// state directory first. All paths are fixed by Service.qml and passed as
// positional arguments rather than interpolated into this program.
var keep = "set -eu\ncandidate=$1\nmonitors=$2\nplain_candidate=$3\nplain=$4\ntoken=$5\n[ -f \"$candidate\" ] && [ ! -L \"$candidate\" ] || exit 2\n[ -f \"$plain_candidate\" ] && [ ! -L \"$plain_candidate\" ] || exit 2\n[ ! -L \"$monitors\" ] || exit 2\nmkdir -p \"$(dirname \"$monitors\")\" \"$(dirname \"$plain\")\"\nts=$(date +%s)\nbackup=\"${monitors}.bak.${ts}\"\nif [ -f \"$monitors\" ]; then cp -p -- \"$monitors\" \"$backup\"; else : > \"$backup\"; fi\ntmp=$(mktemp \"${monitors}.station.XXXXXX\")\nplain_tmp=$(mktemp \"${plain}.station.XXXXXX\")\ntrap 'rm -f \"$tmp\" \"$plain_tmp\"' EXIT HUP INT TERM\ncp -- \"$candidate\" \"$tmp\"\ncp -- \"$plain_candidate\" \"$plain_tmp\"\nif [ -f \"$monitors\" ]; then chmod --reference=\"$monitors\" \"$tmp\"; else chmod 600 \"$tmp\"; fi\nchmod 600 \"$plain_tmp\"\nmv -- \"$tmp\" \"$monitors\"\n# The accepted preview is already live. Hyprland watches sourced config files,\n# so forcing another reload here only duplicates topology work and can make a\n# disabled output disappear twice. Allow the file watch to settle, then inspect\n# any reported error; an error still restores the backup and forces recovery.\nsleep 1\nerrors=$(hyprctl configerrors)\nif [ -n \"$errors\" ]; then\n  cp -- \"$backup\" \"$monitors\"\n  hyprctl reload >/dev/null\n  printf '%s\\n' \"$errors\" >&2\n  exit 3\nfi\nmv -- \"$plain_tmp\" \"$plain\"\nrm -f -- \"$token\"\nfind \"$(dirname \"$monitors\")\" -maxdepth 1 -type f -name \"$(basename \"$monitors\").bak.*\" -printf '%T@ %p\\n' | sort -rn | awk 'NR > 5 { sub(/^[^ ]+ /, \"\"); print }' | while IFS= read -r old; do rm -f -- \"$old\"; done\ntrap - EXIT HUP INT TERM\n"

// A watchdog belongs to the preview that armed it. previewArm touches the
// token before every apply, so a token younger than the sleep window means a
// newer preview owns the session and this watchdog stands down; only a token
// untouched for the full window reverts. Without that, a rearrangement
// session longer than the window would be rolled back by the first preview's
// watchdog while the user was still editing.
var watchdog = "sleep \"$1\"; [ -e \"$2\" ] || exit 0; age=$(( $(date +%s) - $(stat -c %Y \"$2\") )); [ \"$age\" -lt \"$1\" ] && exit 0; rm -f \"$2\"; hyprctl reload"

if (typeof module !== "undefined") module.exports = { keep: keep, watchdog: watchdog }
