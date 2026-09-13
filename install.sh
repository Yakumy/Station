#!/bin/sh
set -eu

# ---------------------------------------------------------------------------
# Station installer — security model
#
# The prebuilt path's trust rests on two tools: the downloader (curl) and the
# provenance verifier (gh). The source path depends on the builder (bun). If
# any of those can be substituted, the provenance gate can be defeated (a fake
# gh can simply report success). To prevent that, this installer:
#
#   1. Discards the caller's PATH and resolves every command from a fixed,
#      non-ambient search path (system locations first, then the usual
#      per-user tool locations).
#   2. Resolves curl, gh, and bun exactly once, validates that neither the
#      resolved path nor its canonical target is reachable through a
#      directory owned by another user or writable by group/other, and then
#      immediately opens a read-only file descriptor on the validated
#      canonical file. From that point on the tool is invoked exclusively
#      through /proc/self/fd/<n>, which execs the exact inode captured at
#      validation time — a later swap of the path (or of any directory in
#      its resolution chain) cannot substitute a different binary for the
#      one that was actually checked. This closes the gap between
#      "we checked this path" and "we ran this path".
#   3. Runs those three tools with a minimal environment (HOME + trusted PATH
#      only), so loader variables, proxies, or tool-specific configuration
#      cannot redirect or alter their behaviour.
#   4. Stages downloaded/built binaries in a freshly created, randomly named,
#      owner-only directory — never at a predictable pathname — and installs
#      them with an atomic rename.
#   5. Refuses to replace ~/.local/bin/station or station-bindings.lua unless
#      the existing path is demonstrably a Station-owned symlink.
# ---------------------------------------------------------------------------

HOME_DIR="${HOME:?}"
CONFIG_HYPR="$HOME_DIR/.config/hypr"
OMARCHY_PLUGINS="$HOME_DIR/.config/omarchy/plugins"
PLUGIN_ID="yakumy.station"
PLUGIN_DIR="$OMARCHY_PLUGINS/$PLUGIN_ID"

PLUGIN_BIN="$PLUGIN_DIR/bin/station"
VERSION_MARKER="$PLUGIN_DIR/bin/.station-version"
TARGET="$HOME_DIR/.local/bin/station"

STATION_BINDINGS_SOURCE="$PLUGIN_DIR/station-bindings.lua"
STATION_BINDINGS_TARGET="$CONFIG_HYPR/station-bindings.lua"
HYPRLAND_LUA="$CONFIG_HYPR/hyprland.lua"

ANCHOR_ID="omarchy.menu"

REQUIRED_HYPRLAND_MAJOR="0"
REQUIRED_HYPRLAND_MINOR="56"
REQUIRED_OMARCHY_MAJOR="4"

RELEASE_BASE_URL="https://github.com/Yakumy/Station/releases/download"

# Fixed, non-ambient command search path. System locations come first so that
# helper commands (stat, readlink, cut, ...) always resolve to root-owned
# binaries; per-user tool locations follow so that version-manager installs
# remain usable.
SYSTEM_TOOL_PATH="/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
USER_TOOL_PATH="$HOME_DIR/.local/bin:$HOME_DIR/.bun/bin:$HOME_DIR/.cargo/bin:$HOME_DIR/.nix-profile/bin:$HOME_DIR/.local/share/mise/shims"
TRUSTED_PATH="$SYSTEM_TOOL_PATH:$USER_TOOL_PATH"
PATH="$TRUSTED_PATH"
export PATH

SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

die() {
  echo "Station: $*" >&2
  exit 1
}

# Run a security-sensitive tool with a minimal environment. The caller's
# environment is discarded entirely: only HOME and the trusted PATH survive.
run_trusted() {
  env -i \
    HOME="$HOME_DIR" \
    PATH="$TRUSTED_PATH" \
    "$@"
}

# Resolve a tool to a single absolute path and verify that neither the
# resolved path nor its canonical target is reachable through a directory
# owned by another user or writable by group/other. Prints the resolved path
# (which may be a version-manager shim) on success and fails closed otherwise.
resolve_trusted_tool() {
  tool_name="$1"

  tool_path="$(command -v -- "$tool_name" 2>/dev/null || true)"
  case "$tool_path" in
    /*) ;;
    *) return 1 ;;
  esac

  tool_real="$(readlink -f -- "$tool_path" 2>/dev/null || true)"
  if [ -z "$tool_real" ] || [ ! -f "$tool_real" ] || [ ! -x "$tool_real" ]; then
    return 1
  fi

  current_uid="$(id -u)"

  for tool_check in "$tool_path" "$tool_real"; do
    check_path="$tool_check"
    while [ "$check_path" != "/" ]; do
      owner_uid="$(stat -c '%u' -- "$check_path" 2>/dev/null || true)"
      mode="$(stat -c '%a' -- "$check_path" 2>/dev/null || true)"

      if [ -z "$owner_uid" ] || [ -z "$mode" ]; then
        return 1
      fi

      if [ "$owner_uid" != "0" ] && [ "$owner_uid" != "$current_uid" ]; then
        return 1
      fi

      # `stat -c '%a'` is variable-width: it strips leading zeros (mode 007
      # prints as "7", mode 0750 as "750") and gains an extra leading digit
      # when setuid/setgid/sticky is set (mode 1777 prints as "1777"). Pad
      # to at least 3 digits and always take the *last two* characters, so
      # the group/other write bits are read from the correct position
      # regardless of which of those shapes stat produced. A fixed-offset
      # read (e.g. always character 2 and 3) misreads a 4-digit mode and
      # can silently accept a genuinely world-writable directory.
      case ${#mode} in
        1) mode="00$mode" ;;
        2) mode="0$mode" ;;
      esac
      mode_prefix="${mode%??}"
      last_two="${mode#"$mode_prefix"}"
      group_bit="${last_two%?}"
      other_bit="${last_two#?}"

      case "$group_bit" in
        2|3|6|7) return 1 ;;
      esac
      case "$other_bit" in
        2|3|6|7) return 1 ;;
      esac

      check_path="$(dirname -- "$check_path")"
    done
  done

  printf '%s\n' "$tool_path"
}

# Resolve a tool via resolve_trusted_tool and, on success, immediately open a
# read-only file descriptor on its canonical target, then set
# $OPENED_TOOL_PATH to "/proc/self/fd/<fd_num>" (or "" on any failure).
#
# This must be called directly — never as "$(open_validated_tool ...)" —
# because command substitution runs the call in a subshell, and an `exec`
# done inside a subshell does not survive back into the parent shell. The
# internal call to resolve_trusted_tool below is fine to run via command
# substitution, since resolving a path never touches file descriptors 4-6.
#
# Binding to a file descriptor rather than re-using the checked path closes
# the gap between validation and use: even if the path (or a directory in
# its chain) is replaced immediately afterwards, /proc/self/fd/<n> continues
# to reference the exact inode that was validated, all the way through the
# fork+exec of `env` in run_trusted.
open_validated_tool() {
  tool_name="$1"
  fd_num="$2"
  OPENED_TOOL_PATH=""

  tool_path="$(resolve_trusted_tool "$tool_name" 2>/dev/null)" || return 1
  tool_real="$(readlink -f -- "$tool_path" 2>/dev/null || true)"
  [ -n "$tool_real" ] || return 1

  case "$fd_num" in
      4) exec 4<"$tool_real" || return 1 ;;
      5) exec 5<"$tool_real" || return 1 ;;
      6) exec 6<"$tool_real" || return 1 ;;
      *) return 1 ;;
  esac

  [ -r "/proc/self/fd/$fd_num" ] || return 1
  OPENED_TOOL_PATH="/proc/self/fd/$fd_num"
}

# Resolve and pin each tool exactly once. From here on they are only ever
# invoked through these /proc/self/fd references, never by bare name or by
# a path that could be re-resolved later.
open_validated_tool curl 4 || true
CURL_BIN="$OPENED_TOOL_PATH"

open_validated_tool gh 5 || true
GH_BIN="$OPENED_TOOL_PATH"

open_validated_tool bun 6 || true
BUN_BIN="$OPENED_TOOL_PATH"

# ---------------------------------------------------------------------------
# Secure temporary workspace
#
# Download and build output is staged inside a freshly created, randomly
# named, owner-only directory. No predictable pathname is ever used, so a
# pre-created symlink or file cannot redirect the write.
# ---------------------------------------------------------------------------
TMP_DIR=""

cleanup() {
  if [ -n "$TMP_DIR" ]; then
    rm -rf -- "$TMP_DIR" 2>/dev/null || true
  fi
  exec 4<&- 2>/dev/null || true
  exec 5<&- 2>/dev/null || true
  exec 6<&- 2>/dev/null || true
}
trap cleanup 0

new_temp_dir() {
  mkdir -p -- "$PLUGIN_DIR/bin"
  TMP_DIR="$(mktemp -d "$PLUGIN_DIR/bin/.station-tmp.XXXXXXXX")" || die "could not create a secure temporary directory."
  chmod 700 -- "$TMP_DIR" 2>/dev/null || true
}

# Atomically move a prepared, validated regular file into the plugin binary
# location. rename(2) never follows a destination symlink.
install_binary() {
  staged="$1"

  if [ ! -f "$staged" ] || [ -L "$staged" ] || [ ! -s "$staged" ]; then
    return 1
  fi

  if [ -d "$PLUGIN_BIN" ]; then
    return 1
  fi

  chmod 755 -- "$staged" 2>/dev/null || return 1
  [ -x "$staged" ] || return 1
  mv -f -- "$staged" "$PLUGIN_BIN"
}

# Write the version marker only after the binary itself is in place, so a
# failure can never leave the marker claiming a version the binary does not
# provide.
write_version_marker() {
  marker_tmp="$(mktemp "$PLUGIN_DIR/bin/.station-version.XXXXXXXX")" || return 1
  printf '%s' "$VERSION" > "$marker_tmp" || {
    rm -f -- "$marker_tmp"
    return 1
  }
  chmod 644 -- "$marker_tmp" 2>/dev/null || true
  mv -f -- "$marker_tmp" "$VERSION_MARKER"
}

# Atomically install a symlink by staging it in a fresh temp dir and renaming
# it over the destination.
install_symlink() {
  link_source="$1"
  link_dest="$2"
  link_dir="$(dirname -- "$link_dest")"

  mkdir -p -- "$link_dir"
  link_staging="$(mktemp -d "$link_dir/.station-link.XXXXXXXX")" || return 1

  if ! ln -s -- "$link_source" "$link_staging/link"; then
    rm -rf -- "$link_staging"
    return 1
  fi

  if ! mv -f -- "$link_staging/link" "$link_dest"; then
    rm -rf -- "$link_staging"
    return 1
  fi

  rmdir -- "$link_staging" 2>/dev/null || true
}

install_regular_file() {
  file_source="$1"
  file_dest="$2"
  file_dir="$(dirname -- "$file_dest")"

  mkdir -p -- "$file_dir"
  file_staging="$(mktemp -d "$file_dir/.station-file.XXXXXXXX")" || return 1

  if ! cp -- "$file_source" "$file_staging/file"; then
    rm -rf -- "$file_staging"
    return 1
  fi

  if ! mv -f -- "$file_staging/file" "$file_dest"; then
    rm -rf -- "$file_staging"
    return 1
  fi

  rmdir -- "$file_staging" 2>/dev/null || true
}

# Fail closed unless $owned_path is absent or is a symlink Station itself
# created (i.e. points exactly at $owned_expected).
assert_owned_or_absent() {
  owned_path="$1"
  owned_expected="$2"

  if [ ! -e "$owned_path" ] && [ ! -L "$owned_path" ]; then
    return 0
  fi

  if [ -L "$owned_path" ]; then
    owned_current="$(readlink -- "$owned_path" 2>/dev/null || true)"
    if [ "$owned_current" = "$owned_expected" ]; then
      return 0
    fi

    owned_current_real="$(readlink -f -- "$owned_path" 2>/dev/null || true)"
    owned_expected_real="$(readlink -f -- "$owned_expected" 2>/dev/null || true)"
    if [ -n "$owned_current_real" ] && [ -n "$owned_expected_real" ] && [ "$owned_current_real" = "$owned_expected_real" ]; then
      return 0
    fi

    die "refusing to replace $owned_path — it is a symlink Station does not own (points to: $owned_current)."
  fi

  die "refusing to replace $owned_path — it exists but is not a Station-managed symlink."
}

# ---------------------------------------------------------------------------
# Binary acquisition
# ---------------------------------------------------------------------------

read_version() {
  VERSION="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_DIR/manifest.json" | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')"
  [ -n "$VERSION" ] || die "could not read version from manifest.json."
}

binary_up_to_date() {
  [ -x "$PLUGIN_BIN" ] &&
    [ ! -L "$PLUGIN_BIN" ] &&
    [ -f "$VERSION_MARKER" ] &&
    [ ! -L "$VERSION_MARKER" ] &&
    [ "$(cat "$VERSION_MARKER")" = "$VERSION" ]
}

build_from_source() {
  read_version

  if binary_up_to_date; then
    echo "  Binary: already up to date (v$VERSION)"
    return 0
  fi

  if [ -z "$BUN_BIN" ]; then
    die "'bun' not found or failed trusted-tool validation; cannot build Station from source."
  fi

  echo "  Building Station v$VERSION from source..."
  new_temp_dir

  staged="$TMP_DIR/station"

  if ! run_trusted "$BUN_BIN" build \
    --compile \
    --minify \
    --bytecode \
    "$SOURCE_DIR/index.js" \
    --outfile "$staged"; then
    die "source build failed."
  fi

  if [ ! -x "$staged" ]; then
    die "source build did not produce an executable binary."
  fi

  install_binary "$staged" || die "could not install the built binary."
  write_version_marker || die "could not record the installed version."

  echo "  Binary: built from source (v$VERSION)"
}

fetch_binary() {
  read_version

  if binary_up_to_date; then
    echo "  Binary: already up to date (v$VERSION)"
    return 0
  fi

  if [ -z "$CURL_BIN" ]; then
    die "'curl' not found or failed trusted-tool validation; cannot download the prebuilt binary."
  fi

  if [ -z "$GH_BIN" ]; then
    echo "Station: 'gh' not found or failed trusted-tool validation; cannot verify the prebuilt binary." >&2
    echo "  Install GitHub CLI or use STATION_INSTALL_METHOD=source." >&2
    exit 1
  fi

  echo "  Downloading Station v$VERSION binary..."
  new_temp_dir

  staged="$TMP_DIR/station"
  release_url="${RELEASE_BASE_URL}/v${VERSION}/station"

  # Retain an open descriptor on the staged file and route curl's output
  # through it, so the download cannot be redirected by swapping the path.
  exec 3>"$staged" || die "could not open the staged binary for writing."
  if ! run_trusted "$CURL_BIN" -fsSL "$release_url" >&3; then
    exec 3>&-
    echo "Station: failed to download binary from:" >&2
    echo "  $release_url" >&2
    exit 1
  fi
  exec 3>&-

  echo "  Verifying build provenance..."

  if ! run_trusted "$GH_BIN" attestation verify \
    "$staged" \
    --repo Yakumy/Station \
    --source-ref "refs/tags/v${VERSION}" \
    --signer-workflow "Yakumy/Station/.github/workflows/release.yml" \
    >/dev/null 2>&1; then
    echo "Station: build provenance verification failed." >&2
    echo "  This binary does not match a verified CI build for" >&2
    echo "  Yakumy/Station release v$VERSION. Refusing to install it." >&2
    exit 1
  fi

  install_binary "$staged" || die "could not install the verified binary."
  write_version_marker || die "could not record the installed version."

  echo "  Binary: downloaded and verified (v$VERSION)"
}

# Allow the security test suite to source the helpers above without running
# the installer. When executed (rather than sourced) this is a no-op.
if [ "${STATION_INSTALL_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || true
fi

echo "Station installer"
echo "-----------------"

# ---------------------------------------------------------------------------
# 0. Preflight: verify this is a supported environment before touching
#    anything. Station v1.0.0 targets Omarchy Quattro (Omarchy 4.x+) on
#    Hyprland 0.56.x specifically.
# ---------------------------------------------------------------------------

echo
echo "Station: checking environment..."

if ! command -v hyprctl >/dev/null 2>&1; then
  echo "Station: hyprctl not found. Is Hyprland installed?" >&2
  exit 1
fi

if ! HYPR_VERSION_OUTPUT=$(hyprctl version 2>/dev/null); then
  echo "Station: could not talk to Hyprland (hyprctl version failed)." >&2
  echo "  Is Hyprland actually running right now?" >&2
  exit 1
fi

HYPR_VERSION=$(printf '%s\n' "$HYPR_VERSION_OUTPUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

if [ -z "$HYPR_VERSION" ]; then
  echo "Station: could not determine Hyprland version from 'hyprctl version'." >&2
  exit 1
fi

HYPR_MAJOR=$(printf '%s' "$HYPR_VERSION" | cut -d. -f1)
HYPR_MINOR=$(printf '%s' "$HYPR_VERSION" | cut -d. -f2)

if [ "$HYPR_MAJOR" != "$REQUIRED_HYPRLAND_MAJOR" ] || [ "$HYPR_MINOR" != "$REQUIRED_HYPRLAND_MINOR" ]; then
  echo "Station: unsupported Hyprland version." >&2
  echo "  Station v1.0.0 supports Hyprland ${REQUIRED_HYPRLAND_MAJOR}.${REQUIRED_HYPRLAND_MINOR}.x." >&2
  echo "  Detected: Hyprland $HYPR_VERSION" >&2
  exit 1
fi

echo "  Hyprland: $HYPR_VERSION (supported)"

if ! command -v omarchy >/dev/null 2>&1; then
  echo "Station: 'omarchy' not found." >&2
  echo "  Station v1.0.0 is built specifically for Omarchy Quattro and requires it." >&2
  exit 1
fi

if ! command -v omarchy-version >/dev/null 2>&1; then
  echo "Station: 'omarchy-version' not found; cannot verify Omarchy version." >&2
  exit 1
fi

OMARCHY_VERSION=$(omarchy-version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

if [ -z "$OMARCHY_VERSION" ]; then
  echo "Station: could not determine Omarchy version from 'omarchy-version'." >&2
  exit 1
fi

OMARCHY_MAJOR=$(printf '%s' "$OMARCHY_VERSION" | cut -d. -f1)

if [ "$OMARCHY_MAJOR" -lt "$REQUIRED_OMARCHY_MAJOR" ] 2>/dev/null; then
  echo "Station: unsupported Omarchy version." >&2
  echo "  Station v1.0.0 requires Omarchy ${REQUIRED_OMARCHY_MAJOR}.x (Quattro) or newer." >&2
  echo "  Detected: Omarchy $OMARCHY_VERSION" >&2
  exit 1
fi

echo "  Omarchy: $OMARCHY_VERSION (supported)"
echo

# ---------------------------------------------------------------------------
# 1. Verify required files
# ---------------------------------------------------------------------------

if [ ! -f "$SOURCE_DIR/manifest.json" ]; then
  echo "Station: manifest.json not found in $SOURCE_DIR" >&2
  exit 1
fi

if [ ! -f "$SOURCE_DIR/station-bindings.lua" ]; then
  echo "Station: station-bindings.lua not found:" >&2
  echo "  $SOURCE_DIR/station-bindings.lua" >&2
  exit 1
fi

if [ ! -f "$SOURCE_DIR/station-indicator.qml" ]; then
  echo "Station: station-indicator.qml not found:" >&2
  echo "  $SOURCE_DIR/station-indicator.qml" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Install plugin files
#
# Two modes:
#   production — install.sh is already running from inside the live plugin
#     directory (cloned there by `omarchy plugin add`). The binary is
#     downloaded from the matching GitHub Release, not committed to git.
#   dev — install.sh is running from a standalone local checkout. Copy
#     files into the real plugin directory, using the locally built binary.
# ---------------------------------------------------------------------------

echo
echo "Station: installing plugin files..."

if [ "$SOURCE_DIR" = "$PLUGIN_DIR" ]; then
  MODE="production"
  echo "  Mode: production (running in place)"

  INSTALL_METHOD="${STATION_INSTALL_METHOD:-}"

  case "$INSTALL_METHOD" in
    source)
      build_from_source
      ;;
    prebuilt)
      fetch_binary
      ;;
    "")
      if [ -n "$GH_BIN" ]; then
        fetch_binary
      elif [ -n "$BUN_BIN" ]; then
        echo "  'gh' not found — building from source instead of using the"
        echo "  prebuilt release. (Install 'gh' to use the attested binary"
        echo "  instead, or set STATION_INSTALL_METHOD=prebuilt to require it.)"
        build_from_source
      else
        echo "Station: neither 'gh' nor 'bun' is available." >&2
        echo "  Install 'gh' to use the prebuilt, attested release binary, or" >&2
        echo "  install Bun (https://bun.sh) to build Station from source." >&2
        exit 1
      fi
      ;;
    *)
      die "unknown STATION_INSTALL_METHOD '$INSTALL_METHOD' (use 'prebuilt' or 'source')."
      ;;
  esac
else
  MODE="dev"
  echo "  Mode: dev (copying into $PLUGIN_DIR)"

  SOURCE_BIN="$SOURCE_DIR/bin/station"

  if [ ! -f "$SOURCE_BIN" ] || [ ! -x "$SOURCE_BIN" ] || [ -L "$SOURCE_BIN" ]; then
    echo "Station: compiled binary not found:" >&2
    echo "  $SOURCE_BIN" >&2
    echo >&2
    echo "Build it first with:" >&2
    echo "  bun build --compile --minify --bytecode index.js --outfile bin/station" >&2
    exit 1
  fi

  install_regular_file "$SOURCE_DIR/manifest.json" "$PLUGIN_DIR/manifest.json" || die "could not install manifest.json."
  install_regular_file "$SOURCE_DIR/station-indicator.qml" "$PLUGIN_DIR/station-indicator.qml" || die "could not install station-indicator.qml."
  install_regular_file "$SOURCE_DIR/station-bindings.lua" "$PLUGIN_DIR/station-bindings.lua" || die "could not install station-bindings.lua."

  new_temp_dir
  cp -- "$SOURCE_BIN" "$TMP_DIR/station" || die "could not stage the local binary."
  install_binary "$TMP_DIR/station" || die "could not install the local binary."
fi

echo "  Plugin: $PLUGIN_DIR"
echo "  Binary: $PLUGIN_BIN"

# ---------------------------------------------------------------------------
# 3. Install the user-facing station command
#
# ~/.local/bin is shared with other tools, so an existing path there is only
# replaced when it is a Station-owned symlink to the plugin binary.
# ---------------------------------------------------------------------------

assert_owned_or_absent "$TARGET" "$PLUGIN_BIN"
install_symlink "$PLUGIN_BIN" "$TARGET" || die "could not install the station command."

echo "  Command: $TARGET"

# ---------------------------------------------------------------------------
# 4. Install the Hyprland integration
#
# station-bindings.lua lives in a shared Hyprland config directory and is
# subject to the same ownership check.
# ---------------------------------------------------------------------------

assert_owned_or_absent "$STATION_BINDINGS_TARGET" "$STATION_BINDINGS_SOURCE"
install_symlink "$STATION_BINDINGS_SOURCE" "$STATION_BINDINGS_TARGET" || die "could not install the Hyprland module."

echo "  Hyprland module: $STATION_BINDINGS_TARGET"

if [ -L "$HYPRLAND_LUA" ]; then
  die "$HYPRLAND_LUA is a symlink; refusing to modify it."
fi

if [ ! -f "$HYPRLAND_LUA" ]; then
  echo "Station: $HYPRLAND_LUA does not exist." >&2
  exit 1
fi

if ! grep -Fqx 'require("station-bindings")' "$HYPRLAND_LUA"; then
  HYPR_MODE="$(stat -c '%a' -- "$HYPRLAND_LUA")"
  HYPR_TMP="$(mktemp "$CONFIG_HYPR/.hyprland.lua.XXXXXXXX")" || die "could not stage hyprland.lua."

  if ! cat -- "$HYPRLAND_LUA" > "$HYPR_TMP"; then
    rm -f -- "$HYPR_TMP"
    die "could not stage hyprland.lua."
  fi

  printf '\n-- Station plugin\nrequire("station-bindings")\n' >> "$HYPR_TMP"
  chmod "$HYPR_MODE" -- "$HYPR_TMP" 2>/dev/null || true

  if ! mv -f -- "$HYPR_TMP" "$HYPRLAND_LUA"; then
    rm -f -- "$HYPR_TMP"
    die "could not update hyprland.lua."
  fi

  echo "  Added Station to hyprland.lua"
else
  echo "  Station is already loaded by hyprland.lua"
fi

# ---------------------------------------------------------------------------
# 5. Register/enable the Quattro plugin
# ---------------------------------------------------------------------------

echo
echo "Station: configuring Omarchy plugin..."

if omarchy plugin validate "$PLUGIN_DIR" >/dev/null 2>&1; then
  echo "  Plugin manifest: valid"
else
  echo "Station: plugin validation failed." >&2
  echo "  Run:" >&2
  echo "    omarchy plugin validate $PLUGIN_DIR" >&2
  exit 1
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1; then
  echo "  Plugin: enabled"
else
  echo "Station: could not enable $PLUGIN_ID automatically." >&2
  echo "  Run:" >&2
  echo "    omarchy plugin enable $PLUGIN_ID" >&2
fi

if move_err=$(omarchy bar move "$PLUGIN_ID" --section left --after "$ANCHOR_ID" 2>&1); then
  echo "  Bar: Station placed after $ANCHOR_ID"
else
  echo "Station: couldn't auto-position the bar indicator (non-fatal)." >&2
  if [ -n "$move_err" ]; then
    echo "  $move_err" >&2
  fi
  echo "  You can position it manually with:" >&2
  echo "    omarchy bar move $PLUGIN_ID --section left --after $ANCHOR_ID" >&2
fi

# ---------------------------------------------------------------------------
# 6. Reload Hyprland
# ---------------------------------------------------------------------------

echo

if hyprctl reload >/dev/null 2>&1; then
  echo "  Hyprland: reloaded"
else
  echo "Station: could not reload Hyprland automatically." >&2
fi

# ---------------------------------------------------------------------------
# 7. Restart Omarchy shell
# ---------------------------------------------------------------------------

if command -v omarchy-restart-shell >/dev/null 2>&1; then
  if omarchy-restart-shell >/dev/null 2>&1; then
    echo "  Omarchy shell: restarted"
  else
    echo "Station: could not restart Omarchy shell automatically." >&2
  fi
fi

echo
echo "Station installation complete ($MODE mode)."
echo
echo "Station is installed but not initialized."
echo
echo "Run:"
echo "  station status"
echo
echo "Then activate Station with:"
echo "  station init"
