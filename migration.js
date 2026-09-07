import { hyprEval, hyprJson, sleep } from "./ipc.js";
import { dualWorkspace, singleWorkspace, showStation } from "./workstation.js";

const SETTLE_MS = 20;

function clientsOnWorkspace(id) {
  return hyprJson("clients").filter(
    (client) => Number(client.workspace?.id) === Number(id),
  );
}

async function moveClients(source, target, follow = false) {
  for (const client of clientsOnWorkspace(source)) {
    hyprEval(
      `hl.dispatch(hl.dsp.window.move({ window = ${JSON.stringify(`address:${client.address}`)}, workspace = ${target}, follow = ${follow ? "true" : "false"} }))`,
    );
    await sleep(SETTLE_MS);
  }
}

async function moveWorkspaceToMonitor(workspace, monitor) {
  hyprEval(
    `hl.dispatch(hl.dsp.workspace.move({ workspace = ${workspace}, monitor = ${JSON.stringify(monitor)} }))`,
  );
  await sleep(SETTLE_MS);
}

async function dpms(monitor, action) {
  const connected = hyprJson("monitors").some((m) => m.name === monitor);
  if (!connected) return;
  hyprEval(
    `hl.dispatch(hl.dsp.dpms({ action = ${JSON.stringify(action)}, monitor = ${JSON.stringify(monitor)} }))`,
  );
  await sleep(SETTLE_MS);
}

export async function dualToSingle(state, targetRole, preserveStation = null) {
  const targetMonitor =
    targetRole === "primary" ? state.primary : state.secondary;
  const otherMonitor =
    targetRole === "primary" ? state.secondary : state.primary;

  // Make all ten logical halves available on the surviving monitor before merging.
  for (let station = 1; station <= state.stations; station++) {
    const keep = dualWorkspace(station, targetRole);
    const source = dualWorkspace(
      station,
      targetRole === "primary" ? "secondary" : "primary",
    );
    await moveWorkspaceToMonitor(source, targetMonitor);
    await moveWorkspaceToMonitor(keep, targetMonitor);
  }

  // Merge each station's two halves into the half belonging to the surviving role.
  for (let station = 1; station <= state.stations; station++) {
    const keep = dualWorkspace(station, targetRole);
    const source = dualWorkspace(
      station,
      targetRole === "primary" ? "secondary" : "primary",
    );
    await moveClients(source, keep, false);
  }

  // Collapse odd/even raw IDs into single-monitor IDs 1..5.
  // Ascending order matters here: a station's source position (2n-1 or 2n)
  // is always >= its target position (n), so walking 1->N guarantees each
  // target slot has already been vacated by an earlier iteration before we
  // write into it. Reversing this order reintroduces the merge bug where
  // one station's windows land on top of another's.
  for (let station = 1; station <= state.stations; station++) {
    const source = dualWorkspace(station, targetRole);
    const target = singleWorkspace(station);
    if (source !== target) await moveClients(source, target, false);
  }

  await showSingleWorkspaces(targetMonitor, state.stations);
  await dpms(otherMonitor, "off");
  await dpms(targetMonitor, "on");
  const stationToShow =
    Number.isInteger(preserveStation) &&
    preserveStation >= 1 &&
    preserveStation <= state.stations
      ? preserveStation
      : 1;

  await showStation(
    {
      ...state,
      mode: "single",
      singleRole: targetRole,
    },
    stationToShow,
  );
}

async function showSingleWorkspaces(monitor, stations) {
  // Ensure the final 1..5 workspaces live on the selected monitor.
  for (let station = 1; station <= stations; station++) {
    await moveWorkspaceToMonitor(station, monitor);
  }
}

export async function singleToDual(state, preserveStation = null) {
  const monitors = hyprJson("monitors");
  const primaryPresent = monitors.some((m) => m.name === state.primary);
  const secondaryPresent = monitors.some((m) => m.name === state.secondary);
  if (!primaryPresent || !secondaryPresent)
    throw new Error(
      "Both configured monitors must be connected before leaving single mode.",
    );

  const survivingRole = state.singleRole || "primary";
  const retainedRole = survivingRole;

  // Recreate both workspace halves on their assigned monitors, but preserve the windows
  // where they physically lived during single mode by moving each station wholesale to
  // the surviving half. The other half stays clean.
  for (let station = state.stations; station >= 1; station--) {
    const source = singleWorkspace(station);
    const target = dualWorkspace(station, retainedRole);
    await moveWorkspaceToMonitor(
      target,
      retainedRole === "primary" ? state.primary : state.secondary,
    );
    if (source !== target) await moveClients(source, target, false);
  }

  const otherRole = retainedRole === "primary" ? "secondary" : "primary";
  for (let station = 1; station <= state.stations; station++) {
    const emptyHalf = dualWorkspace(station, otherRole);
    await moveWorkspaceToMonitor(
      emptyHalf,
      otherRole === "primary" ? state.primary : state.secondary,
    );
  }

  await dpms(state.primary, "on");
  await dpms(state.secondary, "on");
  await sleep(SETTLE_MS);
  const stationToShow =
    Number.isInteger(preserveStation) &&
    preserveStation >= 1 &&
    preserveStation <= state.stations
      ? preserveStation
      : 1;

  await showStation(
    {
      ...state,
      mode: "dual",
    },
    stationToShow,
  );
}
