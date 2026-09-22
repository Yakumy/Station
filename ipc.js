import net from "node:net";
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import {
  resolveTrustedSystemTool,
  trustedToolEnvironment,
} from "./tools.js";

const HOME = homedir();

function runHyprctl(args) {
  const hyprctl = resolveTrustedSystemTool("hyprctl");
  if (!hyprctl) {
    throw new Error("hyprctl is not available from a trusted system path.");
  }

  return spawnSync(hyprctl, args, {
    encoding: "utf8",
    env: trustedToolEnvironment(),
  });
}

function runtimeDir() {
  const candidate =
    process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid?.() ?? 1000}`;
  if (!isAbsolute(candidate)) {
    throw new Error("XDG_RUNTIME_DIR must be an absolute path.");
  }
  return resolve(candidate);
}

function validInstanceSignature(value) {
  return typeof value === "string" && /^[A-Za-z0-9._-]+$/.test(value);
}

function instanceSignature() {
  if (process.env.HYPRLAND_INSTANCE_SIGNATURE) {
    if (!validInstanceSignature(process.env.HYPRLAND_INSTANCE_SIGNATURE)) {
      throw new Error("HYPRLAND_INSTANCE_SIGNATURE contains invalid characters.");
    }
    return process.env.HYPRLAND_INSTANCE_SIGNATURE;
  }
  const root = join(runtimeDir(), "hypr");
  if (!existsSync(root)) return null;
  const dirs = readdirSync(root, { withFileTypes: true }).filter(
    (entry) => entry.isDirectory() && validInstanceSignature(entry.name),
  );
  return dirs[0]?.name ?? null;
}

function socketPath(name) {
  const signature = instanceSignature();
  if (!signature) throw new Error("HYPRLAND_INSTANCE_SIGNATURE is not available.");
  return join(runtimeDir(), "hypr", signature, name);
}

export function hyprControl(message, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath(".socket.sock"));
    const chunks = [];
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn(value);
    };
    const timer = setTimeout(() => {
      socket.destroy();
      finish(reject, new Error(`Hyprland IPC timed out for ${message}`));
    }, timeoutMs);
    socket.on("connect", () => socket.end(message));
    socket.on("data", (chunk) => chunks.push(chunk));
    socket.on("end", () => finish(resolve, Buffer.concat(chunks).toString("utf8")));
    socket.on("error", (err) => finish(reject, err));
  });
}

export function hyprJson(command) {
  const output = runHyprctl(["-j", command]);
  if (output.status !== 0) throw new Error(`hyprctl -j ${command} failed: ${output.stderr?.trim()}`);
  const text = output.stdout?.trim() || "null";
  try { return JSON.parse(text); }
  catch { throw new Error(`Invalid JSON from hyprctl -j ${command}: ${text.slice(0, 300)}`); }
}

export function hyprEval(lua) {
  const output = runHyprctl(["eval", lua]);
  if (output.status !== 0) throw new Error(`hyprctl eval failed: ${output.stderr?.trim() || output.stdout?.trim()}`);
  return output.stdout?.trim() || "";
}

export function hyprVersion() {
  const output = runHyprctl(["version"]);
  if (output.status !== 0) throw new Error(`hyprctl version failed: ${output.stderr?.trim()}`);
  return output.stdout.match(/Hyprland\s+(\d+\.\d+\.\d+)/)?.[1] ?? "0.0.0";
}

export function subscribeHyprEvents(onEvent) {
  const socket = net.createConnection(socketPath(".socket2.sock"));
  let buffer = "";
  socket.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    while (true) {
      const index = buffer.indexOf("\n");
      if (index === -1) break;
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (!line) continue;
      const separator = line.indexOf(">>");
      if (separator === -1) continue;
      onEvent(line.slice(0, separator), line.slice(separator + 2));
    }
  });
  return socket;
}

export async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}
