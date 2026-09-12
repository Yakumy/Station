<img src="./preview.png" alt="Station" width="100%">

# Station

Station is an Omarchy plugin for intelligent multi-monitor management that:

- **Creates logical workstations** by syncing Hyprland workspaces across your monitors into an abstraction we call a **station**.
- **Switches and moves windows across monitors** with fast, keyboard-driven controls.
- **Handles monitor hot-plugging automatically**, adapting between dual- and single-monitor layouts.
- **Preserves your workspace state and position** when monitors are disconnected or reconnected.
- **Integrates natively with Omarchy**, including the Quattro bar and Hyprland configuration.
- **Provides a powerful CLI** for configuring, controlling, and monitoring your stations directly from the terminal.

> [!INFO]
> Station currently supports dual- and single-monitor operation. `station init` requires exactly two connected monitors so Station can establish the primary/secondary workstation layout.

## What it does

Station pairs Hyprland workspaces two at a time. In dual-monitor mode, each station spans one workspace on your primary monitor and one on your secondary — station 1 is workspaces 1 and 2, station 2 is workspaces 3 and 4, and so on up to station 5.

Switching stations moves both halves together. Directional movement lets you cross station boundaries or move a window between the two monitors within a station.

When you're down to one monitor — either by choice (`station mode single`) or because a monitor was disconnected — Station collapses each station's two workspaces into one on the monitor that remains, without losing which window belonged to which station. Reconnect the second monitor and Station expands back to the dual layout automatically.

The bar indicator (`[S1]`–`[S5]`) shows your current station and follows your active theme. It is only shown in dual-monitor mode; in single-monitor mode there is no station ambiguity, so the indicator stays out of the way.

<img src="./docs/assets/station-indicator.png" alt="Station indicator" width="100%">

<div align="center" width="100%">
  <video
    src="https://github.com/user-attachments/assets/f74d1c0c-f4ea-4b0b-a396-f4c87e75d474"
    width="100%"
    controls>
  </video>
</div>

## Requirements

Station targets **Omarchy Quattro (Omarchy 4.x+)** and **Hyprland 0.56.x**.

The installer supports two installation methods. You only need the dependencies for the method you choose:

| Method                     | Required tools               | What happens                                                                          |
| -------------------------- | ---------------------------- | ------------------------------------------------------------------------------------- |
| **Prebuilt + attestation** | `gh` (GitHub CLI) and `curl` | Downloads the release binary and verifies its CI build provenance before installation |
| **Build from source**      | `bun`                        | Builds the binary locally from the source checkout; no downloaded binary is trusted   |

Additional requirement:

- `station init` requires exactly 2 connected monitors.

The installer checks the supported Hyprland and Omarchy versions before modifying the system.

## Install

Install the plugin through Omarchy:

```bash
omarchy plugin add https://github.com/Yakumy/Station.git --enable
cd ~/.config/omarchy/plugins/yakumy.station
./install.sh
```

Then initialize Station:

```bash
station init
```

`omarchy plugin add` clones the plugin into the live Omarchy plugin directory and enables its bar widget.

`install.sh` verifies the environment, installs the Station binary, installs the Hyprland integration, configures the Omarchy bar widget, and reloads the required components.

`station init` is intentionally separate from installation. Installation does not automatically take control of your workspaces.

## Installation methods

### Prebuilt binary with verified CI provenance

This is the recommended installation method when GitHub CLI is available.

When using the prebuilt path, `install.sh`:

1. Reads the Station version from `manifest.json`.
2. Downloads the matching release binary from the `Yakumy/Station` GitHub release.
3. Verifies the binary with GitHub artifact attestation verification.
4. Requires the attestation to:

   - use the SLSA provenance predicate;
   - belong to the `Yakumy/Station` repository;
   - reference the exact release tag being installed;
   - be signed by `Yakumy/Station/.github/workflows/release.yml`.

5. Installs the binary only after verification succeeds.

The installer uses a verification policy equivalent to:

```bash
gh attestation verify <binary> \
  --repo Yakumy/Station \
  --source-ref refs/tags/v<VERSION> \
  --signer-workflow Yakumy/Station/.github/workflows/release.yml
```

A valid attestation from another Station release is not sufficient. The source reference must match the exact release version being installed.

The release workflow builds Station with:

```bash
bun build --compile --minify --bytecode index.js --outfile bin/station
```

using Bun `1.4.2`.

The workflow actions are pinned to immutable commit SHAs in `.github/workflows/release.yml`. CI calculates a SHA-256 checksum for the generated binary and creates a GitHub artifact build-provenance attestation before publishing the release assets.

GitHub CLI authentication is not required to verify public Station attestations.

### Build from source

Station can also be built locally from the checked-out source with Bun.

The installer uses the same build command as the release workflow:

```bash
bun build --compile --minify --bytecode index.js --outfile bin/station
```

The locally generated binary is compiled from the source checkout itself. No prebuilt release binary is downloaded or trusted in this mode.

To explicitly select this method:

```bash
STATION_INSTALL_METHOD=source ./install.sh
```

Bun `1.4.2` is the version used by the project's release workflow.

### Automatic method selection

When no method is forced, `install.sh` uses:

- `gh` available → **prebuilt binary + provenance verification**
- otherwise `bun` available → **local source build**
- neither available → installation stops

You can explicitly select either path:

```bash
STATION_INSTALL_METHOD=prebuilt ./install.sh
STATION_INSTALL_METHOD=source ./install.sh
```

`STATION_INSTALL_METHOD=prebuilt` requires GitHub CLI because provenance verification is mandatory for that path. The installer will not silently install an unverified prebuilt binary.

## Build and release provenance

Station's prebuilt release binary is intentionally not committed to the repository.

Release binaries are produced by:

```text
.github/workflows/release.yml
```

For each release tag, the workflow:

1. Checks out the tagged source.
2. Installs Bun `1.4.2`.
3. Builds `index.js` into the `station` executable.
4. Calculates the binary's SHA-256 checksum.
5. Creates a GitHub artifact build-provenance attestation.
6. Publishes the binary and checksum as release assets.

The installer verifies the downloaded binary's provenance before replacing the installed binary.

The resulting trust chain is:

```text
source commit
    ↓
release tag
    ↓
GitHub Actions workflow
    ↓
compiled binary
    ↓
SHA-256 checksum
    ↓
artifact build-provenance attestation
    ↓
installer verification
    ↓
installation
```

The source-build path is an independent alternative for users who prefer to compile locally rather than use a CI-produced binary.

## Reviewer verification

The release version is maintained in `manifest.json`. To determine it without hardcoding a version number:

```bash
VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' manifest.json \
  | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')

echo "$VERSION"
```

Review the source corresponding to the release:

```bash
git clone https://github.com/Yakumy/Station.git
cd Station

VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' manifest.json \
  | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')

git checkout "v$VERSION"
```

Inspect the release workflow and confirm that its actions are pinned:

```bash
sed -n '1,200p' .github/workflows/release.yml
```

Confirm the expected Bun version and source build:

```bash
bun --version
bun build --compile --minify --bytecode index.js --outfile bin/station
```

Verify the public release artifact using the same provenance policy enforced by the installer:

```bash
gh release download "v$VERSION" \
  --repo Yakumy/Station \
  --pattern station \
  --output /tmp/station \
  --clobber

gh attestation verify /tmp/station \
  --repo Yakumy/Station \
  --source-ref "refs/tags/v$VERSION" \
  --signer-workflow Yakumy/Station/.github/workflows/release.yml
```

The installer performs the same exact-release provenance check automatically before installing a prebuilt binary.

## Update

```bash
station update
```

This checks whether a newer version is available, shows the version change, asks for confirmation, then downloads and verifies the new binary using the same provenance policy before replacing the installed version.

Your Station configuration — including primary/secondary monitor selection, direction, and current mode — is stored outside the plugin directory and is not replaced by a normal update.

## Uninstall

```bash
station delete
```

This removes the `station` command, saved Station configuration, Hyprland integration, the bar indicator entry, and the plugin itself.

If any step cannot be completed automatically, Station prints the exact manual command needed to finish the cleanup.

## Configuration

```bash
station set monitor <name> <primary|secondary>
# Example:
station set monitor HDMI-A-2 primary

station direction <left2right|right2left>
# Print the current direction:
station direction

station mode single <primary|secondary>
station mode dual
```

`station set monitor` requires dual-monitor mode with exactly two monitors connected.

By default, Station selects the monitor positioned at `0x0` as the primary monitor. An explicit monitor selection overrides that default.

## Keybindings reference

| Keys                                              | Action                                                                    |
| ------------------------------------------------- | ------------------------------------------------------------------------- |
| `Ctrl + Super + F1`–`F5`                          | Switch to station 1–5                                                     |
| `Shift + Ctrl + Super + F1`–`F5`                  | Move the active window to station 1–5 and follow it                       |
| `Shift + Super + Alt + F1`–`F5`                   | Move the active window to station 1–5 without following                   |
| `Ctrl + Super + Left / Right`                     | Switch to the previous/next station according to the configured direction |
| `Shift + Ctrl + Super + Left / Right / Up / Down` | Move the active window across station or monitor boundaries               |

These keybindings remain available in single-monitor mode. With one monitor, a station and a Hyprland workspace represent the same logical location.

## Troubleshooting / Recovery

**The indicator isn't showing up.**

The indicator is shown when Station is initialized and running in dual-monitor mode.

Check:

```bash
station status
```

If Station is not initialized, run:

```bash
station init
```

If Station reports single-monitor mode, the missing indicator is expected.

**A mode switch seems to have left windows in the wrong place.**

Check:

```bash
station status
hyprctl workspaces
```

Then re-run the desired mode command:

```bash
station mode dual
```

or:

```bash
station mode single <primary|secondary>
```

Mode transitions are designed to be safe to repeat.

**You unplugged a monitor and things look wrong.**

Station listens for Hyprland monitor add/remove events and reconciles its workspace layout automatically.

To force a manual reconciliation:

```bash
station reconcile
```

**You see a Hyprland error immediately after installation.**

The Station integration is designed to remain inactive until Station is initialized. Run:

```bash
station init
```

If the error remains afterward, open an issue with the exact error text.

**You want to start over without reinstalling.**

```bash
station stop
station init
```

`station stop` disables Station without removing the installation. `station init` reinitializes the Station state and respects a previously selected monitor configuration.

**You want a completely clean reset.**

```bash
station delete
```

Then reinstall:

```bash
omarchy plugin add https://github.com/Yakumy/Station.git --enable
cd ~/.config/omarchy/plugins/yakumy.station
./install.sh
station init
```

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
