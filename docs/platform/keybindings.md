<!-- summary: How Hyprland and Omarchy report, register and remove binds, code: keys, modifier order. -->
<!-- code: lib/keybindings/** -->
# Keybinding behavior

## Keybindings

| Fact | Tag |
|---|---|
| `hyprctl eval 'o.bind("SUPER + code:10", "desc", "notify-send x")'` returns `ok`; a **real physical** Super+1 press fired it. | [LIVE] |
| `hyprctl binds -j` reports Lua binds with `dispatcher: "__lua"`, an opaque `arg` (an id such as `17`), `modmask` (SUPER = 64), and `description`. For `code:` binds `key` is `""` and `keycode` is `0`; for a named key such as `F11` `key` shows `"F11"`. **The JSON cannot tell you which keycode a Lua bind uses.** A `jq` filter on `key == "code:10"` or `"10"` matches nothing. | [LIVE] |
| `hl.bind("SUPER + code:10", …)` through the raw API produced an entry with empty key and keycode 0; the Omarchy wrapper `o.bind` is what Omarchy itself uses and what works. | [LIVE] |
| Synthetic keypresses (virtual input) did **not** trigger binds in the test harness. Test bindings with a human keypress. | [LIVE] |
| `hyprctl reload` removes runtime binds (both `hl.bind` and `o.bind`). `configreloaded` follows; re-apply afterwards. | [LIVE] |
| **Binding the same combo twice leaves two entries and both commands fire** (A then B). `hl.unbind(combo)` removes **all** entries on that combo. `hl.unbind` followed by `o.bind` leaves exactly one. | [LIVE] |
| On this Lua provider, use the **registered modifier spelling/order** when unbinding. `CTRL + SUPER + LEFT` left the stock `SUPER + CTRL + LEFT` grouped-focus binding present; matching the stock spelling removed it. Station now uses `SUPER + CTRL + LEFT/RIGHT` for those intentional replacements. | [LIVE] |
| Station's direct `hl.bind(combo, hl.dsp.exec_cmd(command), { description = ... })` path is working on this installation. This supersedes any inference from the earlier raw-bind registration probe that `hl.bind` itself cannot work. The user confirmed the repaired arrows with real keys on 2026-10-05. | [SRC][LIVE] |
| v1.1.10 directional movement first asks Hyprland to move the active window natively. A native tiled move can change position or size without changing workspace/monitor; compare all four after the settle delay before issuing a fallback move. Read `hyprctl activewindow -j` for the actual focus, then track that window by address and identity. | [SRC][LIVE] |
| Omarchy 4 binds workspace keys in a loop with keycodes: `SUPER + code:10…19` switch workspace, `SUPER + SHIFT + code:10…19` move window, `SUPER + SHIFT + ALT + code:10…19` move window silently. `CTRL + SUPER + ←/→` is "Move grouped window focus left/right". `SUPER + SHIFT + ALT + ←/→` moves a whole workspace to another monitor. Source: `$OMARCHY_PATH/default/hypr/bindings/tiling.lua`. 55 declarations containing SUPER and CTRL exist in the defaults. | [LIVE][SRC] |
| **`omarchy menu keybindings --print` is the reliable listing.** It shows defaults, `SUPER + 1…0`, the user's `bindings.lua` entries, **and runtime binds**, with the real display key even when `hyprctl` shows `key:""`. Baseline 227 lines (228 with one extra runtime bind); output identical with `DEBUG=1` and with an empty `XDG_CACHE_HOME`. Format example: `SUPER + 1                           → description`. It uses plain `hyprctl binds` plus a Lua-source-derived cache. Upstream has had an open issue where a scan can die partway so user binds are missed; it did not occur on the test machine. | [LIVE][SRC] |
| Station v2 installed exactly 36 binds (consistent with the action table: 10 switch + 10 send + 10 silent + 2 navigate + 4 move-across; the per-action breakdown is arithmetic, only the total was reported); after a plain shell restart the count stayed 36 with no duplicates. | [LIVE] |
| Hyprland main (after 0.56.2) is expected to report Lua binds differently from `__lua`. Re-check `hyprctl binds -j` shape after upgrades. | [INFER] |
| Physical keypress to completed station switch (compositor bind → timestamp wrapper → `omarchy-shell` IPC → service → finished Hyprland eval), 20 samples: p50 66 ms, p95 68 ms, range 64–69 ms. Shell ping alone, 20 samples: p50 79.75 ms, p95 87.16 ms (ping carries extra overhead). | [LIVE] |
