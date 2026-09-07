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
#     directory (cloned there by `omarchy plugin add`). Files are already
#     in place; nothing to copy.
#   dev — install.sh is running from a standalone local checkout. Copy
#     files into the real plugin directory, same as before.
# ---------------------------------------------------------------------------

echo
echo "Station: installing plugin files..."

if [ "$SOURCE_DIR" = "$PLUGIN_DIR" ]; then
  MODE="production"
  echo "  Mode: production (running in place)"

  if [ ! -x "$PLUGIN_BIN" ]; then
    echo "Station: bin/station is missing or not executable in this checkout." >&2
    echo "  This indicates a broken release — please report this issue." >&2
    exit 1
  fi

  chmod +x "$PLUGIN_BIN"
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
