import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export const STATE_PATH = join(homedir(), ".local", "state", "station", "state.json");
const LOCK_PATH = `${STATE_PATH}.lock`;

export function readState({ fallback = null } = {}) {
  if (!existsSync(STATE_PATH)) return fallback;
  try { return JSON.parse(readFileSync(STATE_PATH, "utf8")); }
  catch { return fallback; }
}

export function writeState(state) {
  mkdirSync(dirname(STATE_PATH), { recursive: true });
  const tmp = `${STATE_PATH}.tmp-${process.pid}`;
  writeFileSync(tmp, JSON.stringify(state, null, 2) + "\n", { mode: 0o600 });
  renameSync(tmp, STATE_PATH);
}

export async function withStateLock(fn) {
  mkdirSync(dirname(LOCK_PATH), { recursive: true });
  const started = Date.now();
  while (true) {
    try {
      mkdirSync(LOCK_PATH);
      break;
    } catch {
      if (Date.now() - started > 4000) throw new Error("Station is busy with another command.");
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  try { return await fn(); }
  finally { rmSync(LOCK_PATH, { recursive: true, force: true }); }
}
