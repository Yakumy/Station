import { existsSync, readFileSync } from "node:fs";

function extractField(body, name) {
  const re = new RegExp(`${name}\\s*=\\s*([\"'])(.*?)\\1`);
  const match = body.match(re);
  return match?.[2] ?? null;
}

export function parseMonitorsLua(path) {
  if (!existsSync(path)) return [];
  const text = readFileSync(path, "utf8");
  const results = [];
  const regex = /hl\.monitor\s*\(\s*\{([\s\S]*?)\}\s*\)/g;
  for (const match of text.matchAll(regex)) {
    const body = match[1];
    const output = extractField(body, "output");
    const position = extractField(body, "position");
    const mode = extractField(body, "mode");
    if (output !== null) results.push({ output, position, mode });
  }
  return results;
}

function sameOutput(monitor, selector) {
  if (!selector) return false;
  if (selector === monitor.name) return true;
  if (
    selector.startsWith("desc:") &&
    selector === `desc:${monitor.description}`
  )
    return true;
  return false;
}

export function resolveOutputSelector(monitors, selector) {
  return monitors.find((monitor) => sameOutput(monitor, selector)) ?? null;
}

export function chooseMonitors(monitors, parsedRules = []) {
  if (monitors.length !== 2) {
    throw new Error("Exactly two active monitors are required.");
  }

  // Station's default rule:
  // the monitor configured at position 0x0 is the primary monitor.
  const zeroRule = parsedRules.find(
    (rule) => rule.position === "0x0" && rule.output,
  );

  if (zeroRule) {
    const primary = resolveOutputSelector(monitors, zeroRule.output);

    if (primary) {
      const secondary = monitors.find((m) => m.name !== primary.name);
      return {
        primary,
        secondary,
        primarySource: "default",
      };
    }
  }

  // Fallback to Hyprland's live monitor coordinates.
  const primaryCandidates = monitors.filter(
    (monitor) => Number(monitor.x) === 0 && Number(monitor.y) === 0,
  );

  if (primaryCandidates.length === 1) {
    const primary = primaryCandidates[0];
    const secondary = monitors.find((m) => m.name !== primary.name);

    return {
      primary,
      secondary,
      primarySource: "default",
    };
  }

  throw new Error(
    "Could not determine the primary monitor. Station requires exactly one monitor at position 0x0.",
  );
}
