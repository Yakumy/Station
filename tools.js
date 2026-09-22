import { realpathSync, statSync } from "node:fs";
import { dirname, join } from "node:path";

export const TRUSTED_SYSTEM_PATH =
  "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin";

const TRUSTED_SYSTEM_DIRS = TRUSTED_SYSTEM_PATH.split(":");
const SYSTEM_OWNER_UID = statSync("/").uid;

const RUNTIME_ENVIRONMENT_KEYS = [
  "DISPLAY",
  "HOME",
  "HYPRLAND_INSTANCE_SIGNATURE",
  "USER",
  "WAYLAND_DISPLAY",
  "XDG_CONFIG_HOME",
  "XDG_CURRENT_DESKTOP",
  "XDG_DATA_HOME",
  "XDG_RUNTIME_DIR",
  "XDG_STATE_HOME",
];

function isSystemOwnedAndNotWritableByOthers(path) {
  let current = path;

  while (true) {
    const metadata = statSync(current);
    if (metadata.uid !== SYSTEM_OWNER_UID || (metadata.mode & 0o022) !== 0) {
      return false;
    }
    if (current === "/") break;
    current = dirname(current);
  }

  return true;
}

export function resolveTrustedSystemTool(name) {
  if (!/^[A-Za-z0-9._+-]+$/.test(name)) return null;

  for (const directory of TRUSTED_SYSTEM_DIRS) {
    try {
      const resolved = realpathSync(join(directory, name));
      const metadata = statSync(resolved);

      if (!metadata.isFile() || (metadata.mode & 0o111) === 0) continue;
      if (!isSystemOwnedAndNotWritableByOthers(resolved)) continue;

      return resolved;
    } catch {
      // Try the next fixed system directory.
    }
  }

  return null;
}

export function trustedToolEnvironment() {
  const environment = {
    LC_ALL: "C.UTF-8",
    PATH: TRUSTED_SYSTEM_PATH,
  };

  for (const key of RUNTIME_ENVIRONMENT_KEYS) {
    if (process.env[key] !== undefined) environment[key] = process.env[key];
  }

  return environment;
}
