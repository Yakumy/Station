// Fixed transaction template. Candidate files are written inside Station's
// state directory first. All paths are fixed by Service.qml and passed as
// positional arguments rather than interpolated into this program.
var keep = "set -eu\ncandidate=$1\nmonitors=$2\nplain_candidate=$3\nplain=$4\ntoken=$5\nbefore=${6-}\ntoggle=${7-}\ntoggle_before=${8-}\n[ -f \"$candidate\" ] && [ ! -L \"$candidate\" ] || exit 2\n[ -f \"$plain_candidate\" ] && [ ! -L \"$plain_candidate\" ] || exit 2\n[ ! -L \"$monitors\" ] || exit 2\nmkdir -p \"$(dirname \"$monitors\")\" \"$(dirname \"$plain\")\"\nts=$(date +%s)\nbackup=\"${monitors}.bak.${ts}\"\nif [ -f \"$monitors\" ]; then cp -p -- \"$monitors\" \"$backup\"; else : > \"$backup\"; fi\ntmp=$(mktemp \"${monitors}.station.XXXXXX\")\nplain_tmp=$(mktemp \"${plain}.station.XXXXXX\")\ntoggle_backup=\ntoggle_moved=0\nauto_restore=\nwritten=0\ncommitted=0\nrestore_auto() {\n  case \"$auto_restore\" in\n    true) hyprctl eval 'hl.config({misc={disable_autoreload=true}})' >/dev/null ;;\n    false) hyprctl eval 'hl.config({misc={disable_autoreload=false}})' >/dev/null ;;\n  esac\n}\nfinish() {\n  result=$?\n  trap - EXIT HUP INT TERM\n  if [ \"$committed\" = 0 ]; then\n    if [ \"$written\" = 1 ] && cmp -s \"$candidate\" \"$monitors\"; then\n      cp -- \"$backup\" \"$monitors\"\n    fi\n    if [ \"$toggle_moved\" = 1 ] && [ -f \"$toggle_backup\" ] && [ ! -e \"$toggle\" ] && [ ! -L \"$toggle\" ]; then\n      mv -- \"$toggle_backup\" \"$toggle\"\n    fi\n    if [ \"$written\" = 1 ] || [ \"$toggle_moved\" = 1 ]; then hyprctl reload >/dev/null || true; fi\n  fi\n  restore_auto || true\n  rm -f -- \"$tmp\" \"$plain_tmp\"\n  exit \"$result\"\n}\ntrap finish EXIT\ntrap 'exit 2' HUP INT TERM\ncp -- \"$candidate\" \"$tmp\"\nif [ -f \"$monitors\" ]; then chmod --reference=\"$monitors\" \"$tmp\"; else chmod 600 \"$tmp\"; fi\nchmod 600 \"$plain_tmp\"\nif [ \"$#\" -ge 6 ]; then\n  printf '%s' \"$before\" > \"$plain_tmp\"\n  if [ -f \"$monitors\" ]; then cmp -s \"$plain_tmp\" \"$monitors\" || exit 4; else [ ! -s \"$plain_tmp\" ] || exit 4; fi\nfi\nif [ -n \"$toggle_before\" ]; then\n  [ -f \"$toggle\" ] && [ ! -L \"$toggle\" ] || exit 4\n  printf '%s' \"$toggle_before\" > \"$plain_tmp\"\n  cmp -s \"$plain_tmp\" \"$toggle\" || exit 4\n  # The two files must be applied together, never with the old disable flag.\n  auto_restore=$(hyprctl getoption misc:disable_autoreload -j | jq -er '.bool | tostring')\n  case \"$auto_restore\" in true|false) ;; *) exit 2;; esac\n  [ \"$(hyprctl eval 'hl.config({misc={disable_autoreload=true}})')\" = ok ] || exit 2\n  cmp -s \"$plain_tmp\" \"$toggle\" || exit 4\n  toggle_backup=$(mktemp \"${toggle}.station-backup.XXXXXX\")\n  mv -- \"$toggle\" \"$toggle_backup\"\n  toggle_moved=1\nfi\ncp -- \"$plain_candidate\" \"$plain_tmp\"\nmv -- \"$tmp\" \"$monitors\"\nwritten=1\nif [ -n \"$toggle_backup\" ]; then\n  hyprctl reload >/dev/null\n  restore_auto\nfi\n# Ordinary Keep relies on the watched apply; only a multi-file toggle handoff\n# explicitly reloads once while automatic reloads are suspended.\nsleep 1\nerrors=$(hyprctl configerrors)\nif [ -n \"$errors\" ]; then\n  printf '%s\\n' \"$errors\" >&2\n  exit 3\nfi\nmv -- \"$plain_tmp\" \"$plain\"\nrm -f -- \"$token\"\ncommitted=1\nif [ -n \"$toggle_backup\" ]; then rm -f -- \"$toggle_backup\"; fi\nfind \"$(dirname \"$monitors\")\" -maxdepth 1 -type f -name \"$(basename \"$monitors\").bak.*\" -printf '%T@ %p\\n' | sort -rn | awk 'NR > 5 { sub(/^[^ ]+ /, \"\"); print }' | while IFS= read -r old; do rm -f -- \"$old\"; done\n"

// A watchdog belongs to the preview that armed it. previewArm touches the
// token before every apply, so a token younger than the sleep window means a
// newer preview owns the session and this watchdog stands down; only a token
// untouched for the full window reverts. Without that, a rearrangement
// session longer than the window would be rolled back by the first preview's
// watchdog while the user was still editing.
var watchdog = "sleep \"$1\"; [ -e \"$2\" ] || exit 0; age=$(( $(date +%s) - $(stat -c %Y \"$2\") )); [ \"$age\" -lt \"$1\" ] && exit 0; rm -f \"$2\"; if [ -f \"${3-}\" ]; then if [ -e \"$4\" ] || [ -L \"$4\" ]; then rm -f -- \"$3\"; else mv -- \"$3\" \"$4\"; fi; fi; hyprctl reload"

if (typeof module !== "undefined") module.exports = { keep: keep, watchdog: watchdog }

// Moves the exact Omarchy Off flag out of the toggle directory for the length of a
// preview. Removing a loaded file triggers a watched reload, so watches are suspended
// around the move. A parked copy never overwrites a flag written since.
var parkToggle = [
  "set -eu",
  "toggle=$1",
  "parked=$2",
  "before=$3",
  "[ -f \"$toggle\" ] && [ ! -L \"$toggle\" ] || exit 4",
  "base=$(mktemp \"${parked}.base.XXXXXX\")",
  "auto_restore=",
  "restore_auto() {",
  "  case \"$auto_restore\" in",
  "    true) hyprctl eval 'hl.config({misc={disable_autoreload=true}})' >/dev/null ;;",
  "    false) hyprctl eval 'hl.config({misc={disable_autoreload=false}})' >/dev/null ;;",
  "  esac",
  "}",
  "finish() { result=$?; trap - EXIT HUP INT TERM; restore_auto || result=2; rm -f -- \"$base\"; exit \"$result\"; }",
  "trap finish EXIT",
  "trap 'exit 2' HUP INT TERM",
  "printf '%s' \"$before\" > \"$base\"",
  "cmp -s \"$base\" \"$toggle\" || exit 4",
  "auto_restore=$(hyprctl getoption misc:disable_autoreload -j | jq -er '.bool | tostring')",
  "case \"$auto_restore\" in true|false) ;; *) exit 2;; esac",
  "[ \"$(hyprctl eval 'hl.config({misc={disable_autoreload=true}})')\" = ok ] || exit 2",
  "cmp -s \"$base\" \"$toggle\" || exit 4",
  "mv -- \"$toggle\" \"$parked\""
].join("\n") + "\n"

var unparkToggle = "if [ -f \"$1\" ]; then if [ -e \"$2\" ] || [ -L \"$2\" ]; then rm -f -- \"$1\"; else mv -- \"$1\" \"$2\"; fi; fi\n"

if (typeof module !== "undefined") { module.exports.parkToggle = parkToggle; module.exports.unparkToggle = unparkToggle }

// Each write backs up the file it replaces. Keep the newest five of a file's
// Station backups, as Keep does for monitors.lua, so window edits do not pile up.
var pruneBackups = "find \"$(dirname \"$file\")\" -maxdepth 1 -type f -name \"$(basename \"$file\").bak.station.*\" -printf '%T@ %p\\n' | sort -rn | awk 'NR > 5 { sub(/^[^ ]+ /, \"\"); print }' | while IFS= read -r old; do rm -f -- \"$old\"; done\n"
if (typeof module !== "undefined") module.exports.pruneBackups = pruneBackups

// Compare before replacing; rollback never overwrites a later external edit.
var settings = "set -eu\nfile=$1\nbefore=$2\nafter=$3\n[ ! -L \"$file\" ] || exit 2\n[ ! -e \"$file\" ] || [ -f \"$file\" ] || exit 2\nmkdir -p \"$(dirname \"$file\")\"\ntmp=$(mktemp \"${file}.station.XXXXXX\")\nbase=$(mktemp \"${file}.station-base.XXXXXX\")\ntrap 'rm -f \"$tmp\" \"$base\"' EXIT HUP INT TERM\nprintf '%s' \"$before\" > \"$base\"\nprintf '%s' \"$after\" > \"$tmp\"\nif [ -f \"$file\" ]; then\n  cmp -s \"$base\" \"$file\" || exit 4\n  chmod --reference=\"$file\" \"$tmp\"\nelse\n  [ ! -s \"$base\" ] || exit 4\n  chmod 600 \"$tmp\"\nfi\nbackup=\"${file}.bak.station.$(date +%s)\"\ncp -p -- \"$base\" \"$backup\"\nmv -- \"$tmp\" \"$file\"\nsleep 1\nerrors=$(hyprctl configerrors) || exit 3\nif [ -n \"$errors\" ]; then\n  printf '%s' \"$after\" > \"$tmp\"\n  cmp -s \"$tmp\" \"$file\" || exit 4\n  cp -- \"$backup\" \"$file\"\n  hyprctl reload >/dev/null\n  printf '%s\\n' \"$errors\" >&2\n  exit 3\nfi\n" + pruneBackups
if (typeof module !== "undefined") module.exports.settings = settings

// Explicit window edits apply directly; only failure recovery reloads Hyprland.
var windowSetting = [
  "set -eu",
  "file=$1",
  "before=$2",
  "after=$3",
  "lua=$4",
  "[ ! -L \"$file\" ] || exit 2",
  "[ ! -e \"$file\" ] || [ -f \"$file\" ] || exit 2",
  "mkdir -p \"$(dirname \"$file\")\"",
  "tmp=$(mktemp \"${file}.station.XXXXXX\")",
  "base=$(mktemp \"${file}.station-base.XXXXXX\")",
  "auto_restore=",
  "candidate=",
  "written=0",
  "committed=0",
  "restore_auto() {",
  "  case \"$auto_restore\" in",
  "    true) [ \"$(hyprctl eval 'hl.config({misc={disable_autoreload=true}})')\" = ok ] ;;",
  "    false) [ \"$(hyprctl eval 'hl.config({misc={disable_autoreload=false}})')\" = ok ] ;;",
  "  esac",
  "}",
  "finish() {",
  "  result=$?",
  "  trap - EXIT HUP INT TERM",
  "  if [ \"$written\" = 1 ] && [ \"$committed\" = 0 ]; then",
  "    # Keep newer external edits; reload current files to recover partial evals.",
  "    if [ ! -L \"$file\" ] && [ -f \"$file\" ] && cmp -s \"$tmp\" \"$file\"; then cp -p -- \"$base\" \"$file\"; fi",
  "    hyprctl reload >/dev/null || true",
  "  fi",
  "  restore_auto || result=3",
  "  rm -f -- \"$tmp\" \"$base\"",
  "  if [ -n \"$candidate\" ]; then rm -f -- \"$candidate\"; fi",
  "  exit \"$result\"",
  "}",
  "trap finish EXIT",
  "trap 'exit 2' HUP INT TERM",
  "printf '%s' \"$before\" > \"$base\"",
  "printf '%s' \"$after\" > \"$tmp\"",
  "compare_source() {",
  "  [ ! -L \"$file\" ] || return 1",
  "  if [ -f \"$file\" ]; then cmp -s \"$base\" \"$file\"; else [ ! -e \"$file\" ] && [ ! -s \"$base\" ]; fi",
  "}",
  "compare_source || exit 4",
  "if [ -f \"$file\" ]; then chmod --reference=\"$file\" \"$tmp\" \"$base\"; else chmod 600 \"$tmp\"; fi",
  "# Removing the watches around our own rename avoids a compositor-wide reload.",
  "auto_restore=$(hyprctl getoption misc:disable_autoreload -j | jq -er '.bool | tostring')",
  "case \"$auto_restore\" in true|false) ;; *) exit 2;; esac",
  "[ \"$(hyprctl eval 'hl.config({misc={disable_autoreload=true}})')\" = ok ] || exit 3",
  "compare_source || exit 4",
  "backup=$(mktemp \"${file}.bak.station.XXXXXX\")",
  "cp -p -- \"$base\" \"$backup\"",
  "# Retain the candidate for conditional rollback after the atomic rename.",
  "candidate=$(mktemp \"${file}.station-apply.XXXXXX\")",
  "cp -p -- \"$tmp\" \"$candidate\"",
  "mv -- \"$candidate\" \"$file\"",
  "written=1",
  "# This compiles the saved file and applies only the explicitly edited setting.",
  "reply=$(hyprctl eval \"$lua\") || { printf '%s\\n' \"$reply\" >&2; exit 3; }",
  "[ \"$reply\" = ok ] || { printf '%s\\n' \"$reply\" >&2; exit 3; }",
  "[ ! -L \"$file\" ] && [ -f \"$file\" ] && cmp -s \"$tmp\" \"$file\" || exit 4",
  "committed=1"
].join("\n") + "\n" + pruneBackups
if (typeof module !== "undefined") module.exports.windowSetting = windowSetting
