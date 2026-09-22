import {
  closeSync,
  constants,
  fstatSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export const STATE_PATH = join(homedir(), ".local", "state", "station", "state.json");
const LOCK_PATH = `${STATE_PATH}.lock`;
const LOCK_OWNER_PATH = join(LOCK_PATH, "owner.json");
const MAX_STATIONS = 5;
const MAX_STATE_BYTES = 64 * 1024;

function isValidState(state) {
  return (
    state !== null &&
    typeof state === "object" &&
    !Array.isArray(state) &&
    state.schema === 1 &&
    typeof state.version === "string" &&
    /^\d+\.\d+\.\d+$/.test(state.version) &&
    typeof state.enabled === "boolean" &&
    ((state.mode === "dual" && state.singleRole === null) ||
      (state.mode === "single" &&
        ["primary", "secondary"].includes(state.singleRole))) &&
    typeof state.primary === "string" &&
    state.primary.length > 0 &&
    state.primary.length <= 256 &&
    typeof state.secondary === "string" &&
    state.secondary.length > 0 &&
    state.secondary.length <= 256 &&
    state.primary !== state.secondary &&
    ["left2right", "right2left"].includes(state.direction) &&
    Number.isInteger(state.stations) &&
    state.stations >= 1 &&
    state.stations <= MAX_STATIONS
  );
}

function lstatOrNull(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw error;
  }
}

function ensureStateDirectory() {
  const stateDirectory = dirname(STATE_PATH);
  mkdirSync(stateDirectory, { recursive: true, mode: 0o700 });
  const metadata = lstatSync(stateDirectory);

  if (!metadata.isDirectory() || metadata.isSymbolicLink()) {
    throw new Error(`Refusing to use non-regular state directory: ${stateDirectory}`);
  }

  return stateDirectory;
}

export function readState({ fallback = null } = {}) {
  let descriptor = null;
  try {
    descriptor = openSync(
      STATE_PATH,
      constants.O_RDONLY | constants.O_NOFOLLOW,
    );
    const metadata = fstatSync(descriptor);
    if (!metadata.isFile() || metadata.size > MAX_STATE_BYTES) return fallback;
    const state = JSON.parse(readFileSync(descriptor, "utf8"));
    return isValidState(state) ? state : fallback;
  } catch {
    return fallback;
  } finally {
    if (descriptor !== null) closeSync(descriptor);
  }
}

export function writeState(state) {
  if (!isValidState(state)) throw new Error("Refusing to write invalid Station state.");

  const stateDirectory = ensureStateDirectory();

  const existing = lstatOrNull(STATE_PATH);
  if (existing && (!existing.isFile() || existing.isSymbolicLink())) {
    throw new Error(`Refusing to replace non-regular state file: ${STATE_PATH}`);
  }

  const stagingDirectory = mkdtempSync(join(stateDirectory, ".state-"));
  const stagedState = join(stagingDirectory, "state.json");
  try {
    writeFileSync(stagedState, JSON.stringify(state, null, 2) + "\n", {
      mode: 0o600,
      flag: "wx",
    });

    const current = lstatOrNull(STATE_PATH);
    if (
      (existing === null && current !== null) ||
      (existing !== null &&
        (current === null ||
          current.isSymbolicLink() ||
          !current.isFile() ||
          current.dev !== existing.dev ||
          current.ino !== existing.ino))
    ) {
      throw new Error(`Refusing to replace changed state file: ${STATE_PATH}`);
    }

    renameSync(stagedState, STATE_PATH);
  } finally {
    rmSync(stagingDirectory, { recursive: true, force: true });
  }
}

function lockIsStale() {
  try {
    const owner = JSON.parse(readFileSync(LOCK_OWNER_PATH, "utf8"));
    if (Number.isInteger(owner.pid) && owner.pid > 0) {
      try {
        process.kill(owner.pid, 0);
        return false;
      } catch (error) {
        return error?.code === "ESRCH";
      }
    }
  } catch {
    // A legacy or interrupted lock has no usable owner metadata.
  }

  try {
    return Date.now() - statSync(LOCK_PATH).mtimeMs > 30_000;
  } catch {
    return true;
  }
}

export async function withStateLock(fn) {
  ensureStateDirectory();
  const started = Date.now();
  const token = randomUUID();
  while (true) {
    let createdLock = false;
    try {
      mkdirSync(LOCK_PATH, { mode: 0o700 });
      createdLock = true;
      writeFileSync(
        LOCK_OWNER_PATH,
        JSON.stringify({ pid: process.pid, token }) + "\n",
        { mode: 0o600, flag: "wx" },
      );
      break;
    } catch (error) {
      if (createdLock) {
        rmSync(LOCK_PATH, { recursive: true, force: true });
        throw error;
      }
      if (error?.code === "EEXIST" && lockIsStale()) {
        rmSync(LOCK_PATH, { recursive: true, force: true });
        continue;
      }
      if (Date.now() - started > 4000) throw new Error("Station is busy with another command.");
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  try {
    return await fn();
  } finally {
    try {
      const owner = JSON.parse(readFileSync(LOCK_OWNER_PATH, "utf8"));
      if (owner.token === token) {
        rmSync(LOCK_PATH, { recursive: true, force: true });
      }
    } catch {
      // Never remove a lock whose ownership can no longer be established.
    }
  }
}
