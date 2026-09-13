#!/usr/bin/env bun

import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir, tmpdir, arch, platform } from "node:os";
import { spawnSync, execSync } from "node:child_process";

import { hyprControl, hyprEval, hyprJson, hyprVersion, sleep } from "./ipc.js";
import {
  chooseMonitors,
  parseMonitorsLua,
  resolveOutputSelector,
} from "./parser.js";
import { readState, writeState, withStateLock, STATE_PATH } from "./state.js";
import {
  dualWorkspace,
  singleWorkspace,
  activeStation,
  ensureDualAssignment,
  showStation,
  moveActiveWindowToStation,
  moveActiveWindowDirectional,
  setRawWorkspaceRules,
  stationDelta,
} from "./workstation.js";
import { dualToSingle, singleToDual } from "./migration.js";

const HOME = homedir();
const CONFIG_HYPR = join(HOME, ".config", "hypr");
const HYPRLAND_LUA = join(CONFIG_HYPR, "hyprland.lua");
const STATION_LUA = join(CONFIG_HYPR, "station-bindings.lua");
const LOCAL_BIN = join(HOME, ".local", "bin");
const STATION_LINK = join(LOCAL_BIN, "station");
const ENTRY_FILE = (() => {
  try {
    const real = realpathSync("/proc/self/exe");
    if (!real.endsWith("/bun")) {
      // We're running as our own compiled binary — trust this
      // unconditionally, regardless of what import.meta.url reports
      // (plain --compile and --bytecode apparently resolve it
      // differently, and neither is reliable here).
      return real;
    }
  } catch {}
  // Running under `bun run index.js` directly — /proc/self/exe points
  // at the bun interpreter, not useful. Fall back to the source path.
  return fileURLToPath(import.meta.url);
})();
const PLUGIN_DIR = dirname(dirname(realpathSync(ENTRY_FILE)));
const MANIFEST_PATH = join(PLUGIN_DIR, "manifest.json");
const INSTALLED_STATE_DIR = join(HOME, ".local", "state", "station");
const LOG_PATH = join(INSTALLED_STATE_DIR, "station.log");
const STATION_HYPR_BINDINGS = join(CONFIG_HYPR, "station-bindings.lua");
const SHELL_JSON = join(HOME, ".config/omarchy/shell.json");
const TARGET = join(HOME, ".local/bin/station");
const STATE_DIR = join(HOME, ".local/state/station");
const STATION_PLUGIN_DIR = join(HOME, ".config/omarchy/plugins/yakumy.station");

function removeStationRequire() {
  if (!existsSync(HYPRLAND_LUA)) return false;

  const original = readFileSync(HYPRLAND_LUA, "utf8");

  const updated = original
    .split("\n")
    .filter((line) => line.trim() !== 'require("station-bindings")')
    .join("\n");

  if (updated === original) {
    return false;
  }

  writeFileSync(HYPRLAND_LUA, updated);
  return true;
}

function removeStationBarWidget() {
  if (!existsSync(SHELL_JSON)) return false;

  const original = readFileSync(SHELL_JSON, "utf8");

  let shell;

  try {
    shell = JSON.parse(original);
  } catch (error) {
    throw new Error(`Could not parse ${SHELL_JSON}: ${error.message}`);
  }

  if (!shell.layout) {
    return false;
  }

  let removed = false;

  for (const section of ["left", "center", "right"]) {
    if (!Array.isArray(shell.layout[section])) continue;

    const before = shell.layout[section].length;

    shell.layout[section] = shell.layout[section].filter(
      (item) => item?.id !== "yakumy.station",
    );

    if (shell.layout[section].length !== before) {
      removed = true;
    }
  }

  if (!removed) {
    return false;
  }

  writeFileSync(SHELL_JSON, JSON.stringify(shell, null, 2) + "\n");

  return true;
}

function deleteStation() {
  console.log("Station: removing installation...");

  // Stop Station first if it is active.
  try {
    if (loadStateOrDefault()) {
      stopStation();
    }
  } catch (error) {
    console.warn(`Station: stop encountered an issue: ${error.message}`);
  }

  let changed = false;

  // Remove executable.
  if (existsSync(TARGET)) {
    rmSync(TARGET, { force: true });
    console.log(`  removed ${TARGET}`);
    changed = true;
  }

  // Remove Station state.
  if (existsSync(STATE_DIR)) {
    rmSync(STATE_DIR, {
      recursive: true,
      force: true,
    });

    console.log(`  removed ${STATE_DIR}`);
    changed = true;
  }

  // Remove Station's Hyprland module symlink/file.
  if (existsSync(STATION_HYPR_BINDINGS)) {
    rmSync(STATION_HYPR_BINDINGS, {
      force: true,
    });

    console.log(`  removed ${STATION_HYPR_BINDINGS}`);
    changed = true;
  }

  // Remove exactly our require line from hyprland.lua.
  if (removeStationRequire()) {
    console.log(`  removed Station from ${HYPRLAND_LUA}`);
    changed = true;
  }

  // Remove exactly our bar-widget entry.
  if (removeStationBarWidget()) {
    console.log(`  removed Station from ${SHELL_JSON}`);
    changed = true;
  }

  // Remove the installed plugin copy.
  if (existsSync(STATION_PLUGIN_DIR)) {
    rmSync(STATION_PLUGIN_DIR, {
      recursive: true,
      force: true,
    });

    console.log(`  removed ${STATION_PLUGIN_DIR}`);
    changed = true;
  }

  try {
    execSync("hyprctl reload", {
      stdio: "ignore",
    });

    console.log("  Hyprland configuration reloaded.");
  } catch {
    console.warn("  Could not reload Hyprland automatically.");
  }

  try {
    execSync("omarchy-restart-shell", {
      stdio: "ignore",
    });

    console.log("  Omarchy shell restarted.");
  } catch {
    console.warn("  Could not restart the Omarchy shell automatically.");
  }

  console.log();

  if (changed) {
    console.log("Station has been completely removed.");
  } else {
    console.log("Station was already removed.");
  }
}

const VERSION = JSON.parse(readFileSync(MANIFEST_PATH, "utf8")).version;
const MAX_STATIONS = 5;
const REQUIRED_HYPRLAND_MAJOR = 0;
const REQUIRED_HYPRLAND_MINOR = 56;

function log(message) {
  mkdirSync(INSTALLED_STATE_DIR, { recursive: true });
  writeFileSync(LOG_PATH, `${new Date().toISOString()} ${message}\n`, {
    flag: "a",
  });
}

function die(message, code = 1) {
  console.error(`station: ${message}`);
  process.exit(code);
}

function commandExists(name) {
  return (
    spawnSync("sh", ["-lc", 'command -v -- "$1"', "sh", name], {
      stdio: "ignore",
    }).status === 0
  );
}

function run(name, args, options = {}) {
  const result = spawnSync(name, args, {
    encoding: "utf8",
    stdio: options.stdio ?? ["ignore", "pipe", "pipe"],
    env: process.env,
  });
  if (result.status !== 0 && options.allowFailure !== true) {
    const stderr = String(result.stderr || "").trim();
    throw new Error(`${name} failed${stderr ? `: ${stderr}` : ""}`);
  }
  return String(result.stdout || "").trim();
}

function isSupportedHyprlandVersion(current) {
  const numbers = current
    .match(/(\d+)\.(\d+)\.(\d+)/)
    ?.slice(1)
    .map(Number);
  if (!numbers) return false;
  return (
    numbers[0] === REQUIRED_HYPRLAND_MAJOR &&
    numbers[1] === REQUIRED_HYPRLAND_MINOR
  );
}

function detectPluginDir() {
  const candidate = PLUGIN_DIR;
  if (existsSync(join(candidate, "manifest.json"))) return candidate;
  return null;
}

function ensureHyprlandConfigIntegration() {
  mkdirSync(CONFIG_HYPR, { recursive: true });
  const marker = 'require("station-bindings")';
  if (!existsSync(HYPRLAND_LUA)) {
    writeFileSync(HYPRLAND_LUA, `-- Station integration\n${marker}\n`, "utf8");
    return;
  }
  const original = readFileSync(HYPRLAND_LUA, "utf8");
  if (original.includes(marker)) return;
  const backup = `${HYPRLAND_LUA}.bak.station-${Date.now()}`;
  writeFileSync(backup, original, "utf8");
  writeFileSync(
    HYPRLAND_LUA,
    `${original.trimEnd()}\n\n-- Station plugin\n${marker}\n`,
    "utf8",
  );
}

function removeHyprlandConfigIntegration() {
  if (!existsSync(HYPRLAND_LUA)) return;
  const marker = 'require("station-bindings")';
  const text = readFileSync(HYPRLAND_LUA, "utf8");
  const next = text
    .split("\n")
    .filter(
      (line) =>
        !line.includes(marker) && !line.trim().includes("-- Station plugin"),
    )
    .join("\n")
    .replace(/\n{3,}$/g, "\n\n");
  writeFileSync(HYPRLAND_LUA, next, "utf8");
}

function ensureBindingsFile() {
  const source = join(PLUGIN_DIR, "station-bindings.lua");
  rmSync(STATION_LUA, { force: true });
  symlinkSync(source, STATION_LUA);
}

function installLauncher() {
  mkdirSync(LOCAL_BIN, { recursive: true });
  const sourceBinary = join(PLUGIN_DIR, "bin", "station");
  if (!existsSync(sourceBinary)) {
    die(
      `compiled binary not found at ${sourceBinary}. Build it first with Bun.`,
    );
  }
  chmodSync(sourceBinary, 0o755);
  rmSync(STATION_LINK, { force: true });
  symlinkSync(sourceBinary, STATION_LINK);
}

function loadStateOrDefault() {
  return readState({ fallback: null });
}

function printMonitors() {
  const monitors = hyprJson("monitors");
  const state = loadStateOrDefault();

  let roles = {
    primary: null,
    secondary: null,
  };

  // Saved Station configuration wins.
  if (state?.primary && state?.secondary) {
    roles.primary = state.primary;
    roles.secondary = state.secondary;
  } else if (monitors.length === 2) {
    // Before initialization, infer the default primary from 0x0.
    const parsedRules = parseMonitorsLua(join(CONFIG_HYPR, "monitors.lua"));

    try {
      const detected = chooseMonitors(monitors, parsedRules);
      roles.primary = detected.primary?.name ?? null;
      roles.secondary = detected.secondary?.name ?? null;
    } catch {
      // Leave roles empty if detection is impossible.
    }
  }

  console.log("ID  NAME        POSITION    SCALE  ROLE");
  console.log("--  ----------  ----------  -----  --------");

  for (const monitor of monitors) {
    let role = "";

    if (monitor.name === roles.primary) {
      role = "primary";
    } else if (monitor.name === roles.secondary) {
      role = "secondary";
    }

    console.log(
      `${String(monitor.id).padEnd(3)} ` +
        `${monitor.name.padEnd(10)} ` +
        `${`${monitor.x}x${monitor.y}`.padEnd(10)}  ` +
        `${String(monitor.scale).padEnd(5)} ` +
        `${role}`,
    );
  }
}

function stateRole(name) {
  const state = readState({ fallback: null });
  if (!state) return null;
  if (state.primary === name) return "PRIMARY";
  if (state.secondary === name) return "SECONDARY";
  return null;
}

async function initStation() {
  if (!commandExists("hyprctl"))
    die("hyprctl is not available in this session.");

  let version;
  try {
    version = hyprVersion();
  } catch {
    die("Could not talk to Hyprland — is it actually running right now?");
  }

  if (!isSupportedHyprlandVersion(version)) {
    die(
      `This version of Station supports Hyprland ${REQUIRED_HYPRLAND_MAJOR}.${REQUIRED_HYPRLAND_MINOR}.x.\n` +
        `Detected: Hyprland ${version}`,
    );
  }
  const monitors = hyprJson("monitors");
  if (monitors.length !== 2) {
    die(
      `Station v1.0.0 requires exactly 2 active monitors; found ${monitors.length}. Connect both monitors and run 'station init' again.`,
    );
  }

  const parsedRules = parseMonitorsLua(join(CONFIG_HYPR, "monitors.lua"));
  const roles = chooseMonitors(monitors, parsedRules);

  const current = loadStateOrDefault();
  const next = {
    schema: 1,
    version: VERSION,
    enabled: true,
    mode: "dual",
    singleRole: null,
    primary: roles.primary.name,
    secondary: roles.secondary.name,
    direction:
      current?.direction === "right2left" ? "right2left" : "left2right",
    stations: MAX_STATIONS,
    initializedAt: current?.initializedAt ?? new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };

  await withStateLock(async () => {
    writeState(next);
  });

  ensureHyprlandConfigIntegration();
  ensureBindingsFile();
  installLauncher();

  await ensureDualAssignment(next);
  setRawWorkspaceRules(next);
  run("hyprctl", ["reload"]);

  console.log(`Station ${VERSION} initialized.`);
  console.log(`Primary:   ${next.primary}`);
  console.log(`Secondary: ${next.secondary}`);
  console.log(`Direction: ${next.direction}`);
  console.log(`Workspaces: primary 1/3/5/7/9, secondary 2/4/6/8/10`);
  console.log(
    "Station indicator will appear after the shell reloads the plugin.",
  );
}

async function stopStation() {
  const state = loadStateOrDefault();
  if (!state) die("Station is not initialized.");
  state.enabled = false;
  state.updatedAt = new Date().toISOString();
  await withStateLock(async () => writeState(state));
  for (const bind of stationBindNames()) {
    try {
      hyprEval(`hl.unbind(${JSON.stringify(bind)})`);
    } catch {}
  }
  try {
    run("hyprctl", ["reload"]);
  } catch {}
  console.log("Station stopped. No migration was performed.");
}

function stationBindNames() {
  const names = [];
  for (let i = 1; i <= MAX_STATIONS; i++) {
    names.push(`CTRL + SUPER + F${i}`);
    names.push(`SHIFT + CTRL + SUPER + F${i}`);
    names.push(`SHIFT + SUPER + ALT + F${i}`);
  }
  names.push("CTRL + SUPER + LEFT", "CTRL + SUPER + RIGHT");
  names.push("SHIFT + CTRL + SUPER + LEFT", "SHIFT + CTRL + SUPER + RIGHT");
  names.push("SHIFT + CTRL + SUPER + UP", "SHIFT + CTRL + SUPER + DOWN");
  return names;
}

async function setMode(mode, role = null) {
  const state = loadStateOrDefault();
  if (!state || !state.enabled)
    die("Station is not initialized or is stopped.");
  if (mode === state.mode && (mode !== "single" || role === state.singleRole)) {
    console.log(`Station is already in ${mode} mode.`);
    return;
  }

  await withStateLock(async () => {
    const preserveStation = activeStation(state);
    if (mode === "single") {
      const targetRole = role || state.singleRole || "primary";
      if (!["primary", "secondary"].includes(targetRole))
        die("single mode requires 'primary' or 'secondary'.");

      if (state.mode === "single" && state.singleRole !== targetRole) {
        // Switching which monitor survives — restore real dual content first,
        // so dualToSingle has genuine per-half data to collapse from.
        await singleToDual(state);
        state.mode = "dual";
        state.singleRole = null;
      }
      await dualToSingle(state, targetRole, preserveStation);
      state.mode = "single";
      state.singleRole = targetRole;
      state.updatedAt = new Date().toISOString();
      writeState(state);
    } else {
      await singleToDual(state, preserveStation);
      state.mode = "dual";
      state.singleRole = null;
      state.updatedAt = new Date().toISOString();
      writeState(state);
    }
  });

  try {
    run("hyprctl", ["reload"]);
  } catch {}
  console.log(
    `Station mode: ${mode}${mode === "single" ? ` (${state.singleRole})` : ""}`,
  );
}

async function switchStation(target) {
  const state = loadStateOrDefault();
  if (!state || !state.enabled) return;
  const current = activeStation(state);
  let n;
  if (target === "prev" || target === "next") {
    const delta = target === "next" ? 1 : -1;
    n = current + delta;
  } else if (target === "left" || target === "right") {
    n = current + stationDelta(target, state.direction);
  } else {
    n = Number(target);
  }
  if (!Number.isInteger(n) || n < 1 || n > state.stations) return;
  await withStateLock(async () => showStation(state, n));
}

async function moveStation(target, silent) {
  const state = loadStateOrDefault();
  if (!state || !state.enabled) return;
  const n = Number(target);
  if (!Number.isInteger(n) || n < 1 || n > state.stations) return;
  await withStateLock(async () =>
    moveActiveWindowToStation(state, n, { silent }),
  );
}

async function moveDir(direction) {
  const state = loadStateOrDefault();
  if (!state || !state.enabled) return;
  await withStateLock(async () =>
    moveActiveWindowDirectional(state, direction),
  );
}

async function reconcile(reason = "manual") {
  const state = loadStateOrDefault();
  if (!state || !state.enabled) return;
  const monitors = hyprJson("monitors");
  if (state.mode === "dual" && monitors.length === 1) {
    const surviving =
      monitors[0].name === state.primary
        ? "primary"
        : monitors[0].name === state.secondary
          ? "secondary"
          : null;
    if (!surviving) return;
    const preserveStation = activeStation(state);
    await withStateLock(async () =>
      dualToSingle(state, surviving, preserveStation),
    );
    state.mode = "single";
    state.singleRole = surviving;
    writeState(state);
    log(`reconcile ${reason}: entered single/${surviving}`);
  } else if (state.mode === "single" && monitors.length === 2) {
    const preserveStation = activeStation(state);
    await withStateLock(async () => singleToDual(state, preserveStation));
    state.mode = "dual";
    state.singleRole = null;
    writeState(state);
    log(`reconcile ${reason}: entered dual`);
  }
}

async function hotplug(kind) {
  await sleep(80);
  await reconcile(`hotplug:${kind}`);
}

function status(json = false) {
  const state = loadStateOrDefault();
  const monitors = hyprJson("monitors");
  const aw = hyprJson("activeworkspace");

  let primary = state?.primary ?? null;
  let secondary = state?.secondary ?? null;
  let primaryIsDefault = false;

  // Before Station is initialized, infer the default monitor roles
  // from ~/.config/hypr/monitors.lua.
  if (!state && monitors.length === 2) {
    const parsedRules = parseMonitorsLua(join(CONFIG_HYPR, "monitors.lua"));

    try {
      const detected = chooseMonitors(monitors, parsedRules);

      primary = detected.primary?.name ?? null;
      secondary = detected.secondary?.name ?? null;
      primaryIsDefault = detected.primarySource === "default";
    } catch {
      // Keep primary/secondary null if detection fails.
    }
  }

  const result = {
    version: VERSION,
    installed: Boolean(state),
    enabled: Boolean(state?.enabled),
    mode: state?.mode ?? null,
    singleRole: state?.singleRole ?? null,
    stations: state?.stations ?? MAX_STATIONS,
    currentStation: state ? activeStation(state) : null,
    direction: state?.direction ?? null,
    primary,
    secondary,
    primaryIsDefault,
    monitorCount: monitors.length,
    activeWorkspace: aw?.id ?? null,
  };

  if (json) {
    console.log(JSON.stringify(result));
    return;
  }

  console.log(`Station ${VERSION}`);
  console.log(
    `Status:       ${
      result.enabled
        ? "active"
        : result.installed
          ? "stopped"
          : "not initialized"
    }`,
  );
  console.log(`Mode:         ${result.mode ?? "-"}`);

  if (result.mode === "single") {
    console.log(`Single:       ${result.singleRole}`);
  }

  console.log(
    `Current:      ${
      result.currentStation ? `S${result.currentStation}` : "-"
    }`,
  );

  console.log(`Direction:    ${result.direction ?? "-"}`);
  console.log(`Monitors:     ${result.monitorCount}`);

  console.log(
    `Primary:      ${
      result.primary
        ? `${result.primary}${result.primaryIsDefault ? " (0x0, default)" : ""}`
        : "-"
    }`,
  );

  console.log(`Secondary:    ${result.secondary ?? "-"}`);
}

function printHelp() {
  console.log(
    `Station ${VERSION}\n\n` +
      `Usage:\n  station init\n  station stop\n  station status [--json]\n  station monitors\n  station set monitor <name> <primary|secondary>\n  station mode single <primary|secondary>\n  station mode dual\n  station direction [left2right|right2left]\n  station switch <1-5|prev|next>\n  station move <1-5>\n  station move-silent <1-5>\n  station move-dir <left|right|up|down>\n  station version\n  station update\n  station delete\n  station help\n\n` +
      `V1.0.0 is intentionally limited to two monitors and five stations (workspaces 1..10).`,
  );
}

async function setMonitor(name, role) {
  const state = loadStateOrDefault();
  if (!state || !state.enabled)
    die("Station is not initialized or is stopped.");
  if (!["primary", "secondary"].includes(role))
    die("role must be primary or secondary.");
  const monitors = hyprJson("monitors");
  const selected = monitors.find((m) => m.name === name);
  if (!selected)
    die(`Monitor '${name}' is not active. Use 'station monitors'.`);
  if (monitors.length !== 2)
    die("Monitor roles can only be changed in dual-monitor mode.");
  const other = monitors.find((m) => m.name !== name);
  state[role] = selected.name;
  state[role === "primary" ? "secondary" : "primary"] = other.name;
  state.mode = "dual";
  state.singleRole = null;
  state.updatedAt = new Date().toISOString();
  await withStateLock(async () => writeState(state));
  await ensureDualAssignment(state);
  setRawWorkspaceRules(state);
  run("hyprctl", ["reload"]);
  console.log(`Primary: ${state.primary}`);
  console.log(`Secondary: ${state.secondary}`);
}

async function setDirection(value) {
  const state = loadStateOrDefault();
  if (!state) die("Station is not initialized.");

  if (value === undefined) {
    console.log(state.direction);
    return;
  }

  if (!["left2right", "right2left"].includes(value)) {
    die("direction must be left2right or right2left.");
  }

  state.direction = value;
  state.updatedAt = new Date().toISOString();

  await withStateLock(async () => writeState(state));

  run("hyprctl", ["reload"]);

  console.log(`Direction: ${value}`);
}

async function update() {
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  const remote = run("git", ["-C", PLUGIN_DIR, "remote", "get-url", "origin"], {
    allowFailure: true,
  });
  if (!remote)
    die(
      "Station was not installed from a git checkout; cannot determine update source.",
    );
  run("git", ["-C", PLUGIN_DIR, "fetch", "--quiet", "origin"]);
  const branch = run(
    "git",
    ["-C", PLUGIN_DIR, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
    { allowFailure: true },
  );
  const ref = branch || "origin/main";
  const remoteManifest = run(
    "git",
    ["-C", PLUGIN_DIR, "show", `${ref}:manifest.json`],
    { allowFailure: true },
  );
  if (!remoteManifest)
    die("Could not read manifest.json from the remote branch.");
  const next = JSON.parse(remoteManifest);
  console.log(`Current version:   ${manifest.version}`);
  console.log(`Available version: ${next.version}`);
  if (manifest.version === next.version) {
    console.log("Already up to date.");
    return;
  }
  process.stdout.write("Update Station now? [y/N] ");
  const answer = await new Promise((resolveAnswer) => {
    process.stdin.setEncoding("utf8");
    process.stdin.once("data", (data) =>
      resolveAnswer(String(data).trim().toLowerCase()),
    );
  });
  if (answer !== "y" && answer !== "yes") {
    console.log("Update cancelled.");
    return;
  }
  run("omarchy", ["plugin", "update", manifest.id, "--yes"]);
  console.log("Reapplying installation steps...");
  run("sh", [join(PLUGIN_DIR, "install.sh")]);
  console.log("Station updated. Existing configuration was preserved.");
}

async function deleteStation() {
  const state = loadStateOrDefault();
  if (!state) die("Station is not initialized.");
  for (const bind of stationBindNames()) {
    try {
      hyprEval(`hl.unbind(${JSON.stringify(bind)})`);
    } catch {}
  }
  removeHyprlandConfigIntegration();
  rmSync(STATION_LUA, { force: true });
  rmSync(STATION_LINK, { force: true });
  rmSync(STATE_PATH, { force: true });
  try {
    run("hyprctl", ["reload"]);
  } catch {}
  console.log("Station integration removed.");
  if (commandExists("omarchy")) {
    try {
      run("omarchy", [
        "plugin",
        "remove",
        JSON.parse(readFileSync(MANIFEST_PATH, "utf8")).id,
        "--yes",
      ]);
      console.log("Station plugin removed from Omarchy.");
      return;
    } catch (error) {
      console.error(
        `station: automatic plugin removal failed: ${error.message}`,
      );
      console.error(
        "Remove the checkout manually with: omarchy plugin remove yakumy.station --yes",
      );
    }
  }
}

async function main() {
  const args = process.argv.slice(2);
  const command = args.shift() || "help";
  try {
    switch (command) {
      case "init":
        return await initStation();
      case "stop":
        return await stopStation();
      case "status":
        return status(args.includes("--json"));
      case "state":
        return status(true);
      case "monitors":
        return printMonitors();
      case "status-monitors":
        return printMonitors();
      case "set":
        if (args[0] === "monitor") return await setMonitor(args[1], args[2]);
        return printHelp();
      case "mode":
        if (args[0] === "single") return await setMode("single", args[1]);
        if (args[0] === "dual") return await setMode("dual");
        return printHelp();
      case "single":
        return await setMode("single", args[0]);
      case "direction":
        return await setDirection(args[0]);
      case "switch":
        return await switchStation(args[0]);
      case "move":
        return await moveStation(args[0], false);
      case "move-silent":
        return await moveStation(args[0], true);
      case "move-dir":
        return await moveDir(args[0]);
      case "reconcile":
        return await reconcile("manual");
      case "hotplug":
        return await hotplug(args[0] || "unknown");
      case "version":
        console.log(VERSION);
        return;
      case "update":
        return await update();
      case "delete":
        return deleteStation();
      case "help":
      case "--help":
      case "-h":
        return printHelp();
      default:
        die(`unknown command '${command}'. Run 'station help'.`);
    }
  } catch (error) {
    log(String(error.stack || error));
    die(error instanceof Error ? error.message : String(error));
  }
}

main();
