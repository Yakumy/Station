import { hyprEval, hyprJson, sleep } from "./ipc.js";
import { readState } from "./state.js";

const PRIMARY_ODDS = [1, 3, 5, 7, 9];
const SECONDARY_EVENS = [2, 4, 6, 8, 10];
const SETTLE_MS = 20;

export function dualWorkspace(station, role) {
  return role === "primary" ? station * 2 - 1 : station * 2;
}

export function singleWorkspace(station) {
  return station;
}

export function activeStation(state) {
  const active = hyprJson("activeworkspace");
  const id = Number(active?.id);
  if (!Number.isInteger(id)) return 1;
  if (state.mode === "single") return Math.max(1, Math.min(state.stations, id));
  if (PRIMARY_ODDS.includes(id)) return (id + 1) / 2;
  if (SECONDARY_EVENS.includes(id)) return id / 2;
  return 1;
}

function activeRole(state) {
  const monitors = hyprJson("monitors");
  const focused = monitors.find((m) => m.focused);
  if (state.mode === "single") return state.singleRole;
  if (focused?.name === state.primary) return "primary";
  if (focused?.name === state.secondary) return "secondary";
  const active = Number(hyprJson("activeworkspace")?.id);
  if (PRIMARY_ODDS.includes(active)) return "primary";
  if (SECONDARY_EVENS.includes(active)) return "secondary";
  return "primary";
}

export async function ensureDualAssignment(state) {
  const monitors = hyprJson("monitors");
  if (monitors.length !== 2) return;
  for (let station = 1; station <= state.stations; station++) {
    await moveWorkspaceToMonitor(
      dualWorkspace(station, "primary"),
      state.primary,
    );
    await moveWorkspaceToMonitor(
      dualWorkspace(station, "secondary"),
      state.secondary,
    );
  }
}

async function moveWorkspaceToMonitor(workspace, monitor) {
  hyprEval(
    `hl.dispatch(hl.dsp.workspace.move({ workspace = ${workspace}, monitor = ${JSON.stringify(monitor)} }))`,
  );
  await sleep(SETTLE_MS);
}

export function setRawWorkspaceRules(state) {
  const pieces = [];
  for (let station = 1; station <= state.stations; station++) {
    pieces.push(
      `hl.workspace_rule({ workspace = "${dualWorkspace(station, "primary")}", monitor = ${JSON.stringify(state.primary)}, persistent = true })`,
    );
    pieces.push(
      `hl.workspace_rule({ workspace = "${dualWorkspace(station, "secondary")}", monitor = ${JSON.stringify(state.secondary)}, persistent = true })`,
    );
  }
  hyprEval(pieces.join(" "));
}

async function focusWorkspace(id) {
  hyprEval(
    `hl.dispatch(hl.dsp.focus({ workspace = ${JSON.stringify(String(id))} }))`,
  );
  await sleep(SETTLE_MS);
}

export async function showStation(state, station) {
  if (state.mode === "single") {
    await focusWorkspace(singleWorkspace(station));
    return;
  }
  const role = activeRole(state);
  const primaryWs = dualWorkspace(station, "primary");
  const secondaryWs = dualWorkspace(station, "secondary");

  // Deliberately mirror the race-safe pattern discovered in Omarchy community testing:
  // focus the other monitor first, then finish on the role we started from.
  if (role === "primary") {
    await focusWorkspace(secondaryWs);
    await focusWorkspace(primaryWs);
  } else {
    await focusWorkspace(primaryWs);
    await focusWorkspace(secondaryWs);
  }
}

function activeClient() {
  const clients = hyprJson("activewindow");
  return clients && clients.address ? clients : null;
}

function allClients() {
  return hyprJson("clients");
}

async function moveWindow(address, workspace, follow) {
  const selector = `address:${address}`;
  hyprEval(
    `hl.dispatch(hl.dsp.window.move({ window = ${JSON.stringify(selector)}, workspace = ${workspace}, follow = ${follow ? "true" : "false"} }))`,
  );
  await sleep(SETTLE_MS);
}

export async function moveActiveWindowToStation(state, station, { silent }) {
  const client = activeClient();
  if (!client?.address) return;
  if (state.mode === "single") {
    await moveWindow(client.address, station, !silent);
    if (!silent) await showStation(state, station);
    return;
  }
  const workspaceId = Number(client.workspace?.id);
  const role =
    Number.isInteger(workspaceId) && workspaceId % 2 === 0
      ? "secondary"
      : "primary";
  const target = dualWorkspace(station, role);
  await moveWindow(client.address, target, !silent);
  if (!silent) {
    await showStation(state, station);
    try {
      hyprEval(
        `hl.dispatch(hl.dsp.focus({ window = ${JSON.stringify(`address:${client.address}`)} }))`,
      );
    } catch {}
  }
}

function monitorForDirection(current, monitors, direction) {
  const center = {
    x: current.x + current.width / 2,
    y: current.y + current.height / 2,
  };

  const candidates = [];

  for (const candidate of monitors) {
    if (candidate.name === current.name) continue;

    const candidateCenter = {
      x: candidate.x + candidate.width / 2,
      y: candidate.y + candidate.height / 2,
    };

    const dx = candidateCenter.x - center.x;
    const dy = candidateCenter.y - center.y;

    if (direction === "right" && dx <= 0) continue;
    if (direction === "left" && dx >= 0) continue;
    if (direction === "down" && dy <= 0) continue;
    if (direction === "up" && dy >= 0) continue;

    const major =
      direction === "left" || direction === "right"
        ? Math.abs(dx)
        : Math.abs(dy);

    const minor =
      direction === "left" || direction === "right"
        ? Math.abs(dy)
        : Math.abs(dx);

    candidates.push({
      candidate,
      score: major + minor * 0.25,
    });
  }

  candidates.sort((a, b) => a.score - b.score);

  return candidates[0]?.candidate ?? null;
}

function clientMonitor(client, monitors) {
  const monitorId = Number(client?.monitor);

  if (Number.isInteger(monitorId)) {
    const byId = monitors.find((monitor) => Number(monitor.id) === monitorId);

    if (byId) return byId;
  }

  // Defensive fallback for future Hyprland output changes.
  if (typeof client?.monitor === "string") {
    return monitors.find((monitor) => monitor.name === client.monitor) ?? null;
  }

  return null;
}

function windowChanged(before, after) {
  if (!before || !after) return false;

  // Workspace changed.
  if (Number(before.workspace?.id) !== Number(after.workspace?.id)) {
    return true;
  }

  // Monitor changed.
  if (Number(before.monitor) !== Number(after.monitor)) {
    return true;
  }

  // Position changed inside the SAME workspace.
  const beforeAt = Array.isArray(before.at) ? before.at : null;

  const afterAt = Array.isArray(after.at) ? after.at : null;

  if (beforeAt && afterAt) {
    if (
      Number(beforeAt[0]) !== Number(afterAt[0]) ||
      Number(beforeAt[1]) !== Number(afterAt[1])
    ) {
      return true;
    }
  }

  // Size can also change as a side effect of a layout operation.
  const beforeSize = Array.isArray(before.size) ? before.size : null;

  const afterSize = Array.isArray(after.size) ? after.size : null;

  if (beforeSize && afterSize) {
    if (
      Number(beforeSize[0]) !== Number(afterSize[0]) ||
      Number(beforeSize[1]) !== Number(afterSize[1])
    ) {
      return true;
    }
  }

  return false;
}

async function tryNativeDirectionalMove(address, direction) {
  const before = allClients().find((client) => client.address === address);

  if (!before) return false;

  hyprEval(
    `hl.dispatch(hl.dsp.window.move({ ` +
      `window = ${JSON.stringify(`address:${address}`)}, ` +
      `direction = ${JSON.stringify(direction)} ` +
      `}))`,
  );

  await sleep(SETTLE_MS);

  const after = allClients().find((client) => client.address === address);

  if (!after) return false;

  return windowChanged(before, after);
}

export function stationDelta(direction, stationDirection) {
  if (direction !== "left" && direction !== "right") {
    return 0;
  }

  if (stationDirection === "left2right") {
    return direction === "right" ? 1 : -1;
  }

  // right2left
  return direction === "left" ? 1 : -1;
}

function horizontalMonitorLayout(monitors) {
  if (monitors.length !== 2) return false;

  const a = monitors[0];
  const b = monitors[1];

  const ax = a.x + a.width / 2;
  const ay = a.y + a.height / 2;

  const bx = b.x + b.width / 2;
  const by = b.y + b.height / 2;

  const dx = Math.abs(bx - ax);
  const dy = Math.abs(by - ay);

  return dx > dy;
}

function roleForStationBoundary(state, currentMonitor, monitors, direction) {
  const horizontal = horizontalMonitorLayout(monitors);

  if (!horizontal) {
    return currentMonitor.name === state.secondary ? "secondary" : "primary";
  }

  /*
   * With two horizontally arranged monitors, crossing a
   * Station boundary moves to the monitor on the opposite
   * physical side.
   */
  return currentMonitor.name === state.primary ? "secondary" : "primary";
}

export async function moveActiveWindowDirectional(state, direction) {
  if (!["left", "right", "up", "down"].includes(direction)) {
    return;
  }

  const client = activeClient();

  if (!client?.address) {
    return;
  }

  /*
   * Single-monitor mode:
   * Station does not own the directional abstraction.
   * Let Hyprland behave normally.
   */
  if (state.mode === "single") {
    hyprEval(
      `hl.dispatch(hl.dsp.window.move({ ` +
        `window = ${JSON.stringify(`address:${client.address}`)}, ` +
        `direction = ${JSON.stringify(direction)} ` +
        `}))`,
    );

    return;
  }

  /*
   * Step 1:
   * Always give normal Hyprland directional movement
   * the first opportunity.
   *
   * This provides the same behavior as:
   *
   *     Shift + Super + Arrow
   *
   * while allowing Station to continue processing when
   * the move actually crossed to another workspace/monitor.
   */
  const nativeMoved = await tryNativeDirectionalMove(client.address, direction);

  if (nativeMoved) {
    return;
  }

  /*
   * Up/Down NEVER changes Station number in V1.
   *
   * If Hyprland could not perform the movement, simply stop.
   */
  if (direction !== "left" && direction !== "right") {
    return;
  }

  const monitors = hyprJson("monitors");

  const currentClient = allClients().find(
    (item) => item.address === client.address,
  );

  if (!currentClient) {
    return;
  }

  /*
   * IMPORTANT:
   * Read the monitor AFTER the native movement attempt.
   * The old client object may contain stale monitor information.
   */
  const currentMonitor = clientMonitor(currentClient, monitors);

  if (!currentMonitor) {
    return;
  }

  /*
   * Step 2:
   * If another monitor physically exists in that direction,
   * this is still movement INSIDE THE SAME STATION.
   *
   * Example:
   *
   *     WS3 → WS4
   */
  const neighbor = monitorForDirection(currentMonitor, monitors, direction);

  if (neighbor) {
    const station = activeStation(state);

    const role = neighbor.name === state.primary ? "primary" : "secondary";

    await moveWindow(client.address, dualWorkspace(station, role), true);

    return;
  }

  /*
   * Step 3:
   * We are at a horizontal/left-right boundary.
   *
   * Determine whether Left or Right means
   * Station +1 or Station -1.
   */
  const currentStation = activeStation(state);

  const delta = stationDelta(direction, state.direction);

  const targetStation = currentStation + delta;

  /*
   * Station boundaries.
   *
   * From S1 + Left:
   *     do nothing
   *
   * From S5 + Right:
   *     do nothing
   */
  if (targetStation < 1 || targetStation > state.stations) {
    return;
  }

  /*
   * Horizontal layout:
   *
   *     S1                    S2
   *   WS1 | WS2    →       WS3 | WS4
   *
   * Crossing the physical right edge:
   *
   *     WS2 → WS5
   *
   * Crossing the physical left edge:
   *
   *     WS3 → WS2
   *
   * Vertical layout:
   *
   *     WS1
   *     ---
   *     WS2
   *
   * Left/right crossing preserves the monitor role:
   *
   *     WS1 → WS3
   *     WS2 → WS4
   */
  const role = roleForStationBoundary(
    state,
    currentMonitor,
    monitors,
    direction,
  );

  const targetWorkspace = dualWorkspace(targetStation, role);

  await moveWindow(client.address, targetWorkspace, true);

  /*
   * Display both workspaces belonging to the destination
   * Station and then explicitly return focus to the moved
   * window.
   */
  await showStation(state, targetStation);

  try {
    hyprEval(
      `hl.dispatch(hl.dsp.focus({ ` +
        `window = ${JSON.stringify(`address:${client.address}`)} ` +
        `}))`,
    );
  } catch {}
}
