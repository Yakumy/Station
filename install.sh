#!/bin/sh
set -eu

SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

HOME_DIR="${HOME:?}"
CONFIG_HYPR="$HOME_DIR/.config/hypr"
OMARCHY_PLUGINS="$HOME_DIR/.config/omarchy/plugins"
PLUGIN_ID="yakumy.station"
PLUGIN_DIR="$OMARCHY_PLUGINS/$PLUGIN_ID"

PLUGIN_BIN="$PLUGIN_DIR/bin/station"
TARGET="$HOME_DIR/.local/bin/station"

STATION_BINDINGS_TARGET="$CONFIG_HYPR/station-bindings.lua"
HYPRLAND_LUA="$CONFIG_HYPR/hyprland.lua"

ANCHOR_ID="omarchy.menu"

REQUIRED_HYPRLAND_MAJOR="0"
REQUIRED_HYPRLAND_MINOR="56"
REQUIRED_OMARCHY_MAJOR="4"

RELEASE_BASE_URL="https://github.com/Yakumy/Station/releases/download"
EXPECTED_SHA256="9ccd010d122295a39d12910103c7d3f0c6c7594726262d1f0caf654b832d7efe"

fetch_binary() {
  VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_DIR/manifest.json" | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')

  if [ -z "$VERSION" ]; then
    echo "Station: could not read version from manifest.json." >&2
    exit 1
  fi

  VERSION_MARKER="$PLUGIN_DIR/bin/.station-version"

  if [ -x "$PLUGIN_BIN" ] && [ -f "$VERSION_MARKER" ] && [ "$(cat "$VERSION_MARKER")" = "$VERSION" ]; then
    echo "  Binary: already up to date (v$VERSION)"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "Station: 'curl' not found; cannot download the prebuilt binary." >&2
    exit 1
  fi

  echo "  Downloading Station v$VERSION binary..."
  mkdir -p "$PLUGIN_DIR/bin"

  if ! curl -fsSL -o "$PLUGIN_BIN" "${RELEASE_BASE_URL}/v${VERSION}/station"; then
    echo "Station: failed to download binary from:" >&2
    echo "  ${RELEASE_BASE_URL}/v${VERSION}/station" >&2
    exit 1
  fi

  ACTUAL_SUM=$(sha256sum "$PLUGIN_BIN" | awk '{print $1}')

  if [ "$ACTUAL_SUM" != "$EXPECTED_SHA256" ]; then
    echo "Station: checksum verification failed for the downloaded binary." >&2
    echo "  Expected (pinned in this reviewed commit): $EXPECTED_SHA256" >&2
    echo "  Actual (downloaded):                       $ACTUAL_SUM" >&2
    echo "  Refusing to install a binary that doesn't match what this" >&2
    echo "  version of Station was reviewed against." >&2
    rm -f "$PLUGIN_BIN"
    exit 1
  fi

  chmod +x "$PLUGIN_BIN"
  printf '%s' "$VERSION" > "$VERSION_MARKER"

  echo "  Binary: downloaded and verified (v$VERSION)"
}

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

  fetch_binary
else
  MODE="dev"
  echo "  Mode: dev (copying into $PLUGIN_DIR)"

  SOURCE_BIN="$SOURCE_DIR/bin/station"

  if [ ! -x "$SOURCE_BIN" ]; then
    echo "Station: compiled binary not found:" >&2
    echo "  $SOURCE_BIN" >&2
    echo >&2
    echo "Build it first with:" >&2
    echo "  bun build --compile --minify --bytecode index.js --outfile bin/station" >&2
    exit 1
  fi

  mkdir -p "$PLUGIN_DIR/bin"

  cp "$SOURCE_DIR/manifest.json" "$PLUGIN_DIR/manifest.json"
  cp "$SOURCE_DIR/station-indicator.qml" "$PLUGIN_DIR/station-indicator.qml"
  cp "$SOURCE_DIR/station-bindings.lua" "$PLUGIN_DIR/station-bindings.lua"
  cp "$SOURCE_BIN" "$PLUGIN_BIN"

  chmod +x "$PLUGIN_BIN"
fi

echo "  Plugin: $PLUGIN_DIR"
echo "  Binary: $PLUGIN_BIN"

# ---------------------------------------------------------------------------
# 3. Install the user-facing station command
# ---------------------------------------------------------------------------

mkdir -p "$HOME_DIR/.local/bin"
rm -f "$TARGET"
ln -s "$PLUGIN_BIN" "$TARGET"

echo "  Command: $TARGET"

# ---------------------------------------------------------------------------
# 4. Install the Hyprland integration
# ---------------------------------------------------------------------------

mkdir -p "$CONFIG_HYPR"
rm -f "$STATION_BINDINGS_TARGET"
ln -s "$PLUGIN_DIR/station-bindings.lua" "$STATION_BINDINGS_TARGET"

echo "  Hyprland module: $STATION_BINDINGS_TARGET"

if [ ! -f "$HYPRLAND_LUA" ]; then
  echo "Station: $HYPRLAND_LUA does not exist." >&2
  exit 1
fi

if ! grep -Fqx 'require("station-bindings")' "$HYPRLAND_LUA"; then
  printf '\n-- Station plugin\nrequire("station-bindings")\n' >> "$HYPRLAND_LUA"
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

# just in order to make a commit, I wrote this line, I fixe the Premision denied error while installing the plugin by running chmod +x install.sh  and now it changed to-rwxr-xr-x from -rw-r--r-- .
