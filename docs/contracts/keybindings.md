<!-- summary: Default combos, IPC methods, conflict sources and statuses, unbind rules, the key picker. -->
<!-- code: lib/keybindings/** -->
# Keybindings

| Action | Default | Replaces |
| --- | --- | --- |
| Switch to station n | `SUPER + 1…0` | Omarchy workspace switch (`SUPER + code:10…19`) |
| Move window to station n, follow | `SUPER + SHIFT + 1…0` | Omarchy move to workspace |
| Move window, no follow | `SUPER + SHIFT + ALT + 1…0` | Omarchy move silently |
| Previous or next station, LTR/RTL | `CTRL + SUPER + Left/Right` | Omarchy grouped-window focus |
| Previous or next station, TTB/BTT | `CTRL + SUPER + Up/Down` | None; personal conflicts require approval |
| Move across outputs and stations | `SUPER + SHIFT + CTRL + arrows` | Omarchy move window to monitor |
| (unbind only) | `SUPER + SHIFT + ALT + arrows` | Omarchy move workspace to monitor, which renumbers the workspace and breaks the map. A personal bind on the combo stays. |

IPC targets the service-owned handler: `omarchy-shell yakumy.station <method> <arg>`.
Its methods are `switchStation`, `sendToStation`, `sendSilent`, `goDirection`,
`shiftWindow`, `togglePanel`, `previewLayout`, `setDisplayEnabled`, `keepPreview`,
`revertPreview`, `setMode`, `setDirection`, `approveBinding` and `status`. All arguments
are validated strings. The `shell call` form reaches only loaded panels, so do not use
it.

Rules for applying binds:

- `hl.unbind` removes every entry on a combo, but only for the modifier order it was
  registered with. A replacement unbinds every order, otherwise both binds stay and both
  fire. Use it only for known Omarchy defaults in the table, combos the user approved,
  and combos in `state.appliedBinds`.
- Do not apply a combo with an unresolved conflict.
- Apply once per configuration generation. A reload clears runtime binds.

Conflict sources, in order:

1. `omarchy menu keybindings --print`. This is the identity source, because
   `hyprctl binds -j` cannot identify Lua `code:` keys.
2. `hyprctl binds -j` as a cross-check for plain keys.
3. A scan of `~/.config/hypr/bindings.lua`.

Station ignores entries whose description starts with `Station:`.

Omarchy 4.5.0 ships its own `SUPER + SHIFT + CTRL + arrow` binds ("Move window to
left/right/up/down monitor"). Station treats them as stock defaults: they are replaced
without a conflict, because Station's `shiftWindow` also crosses stations. Station keeps
its binds so older Omarchy releases still work.

> **Reminder for Station 5.0.0:** Omarchy's binding is then reliable. Remove the four
> `shift-*` definitions in `lib/keybindings/Binds.js` and the `Move window to … monitor`
> entry in `stockOwner`, and drop the Move across section if Omarchy's movement suffices.

| Status | Meaning |
| --- | --- |
| Replacement | A known default or an approved combo. Applied. |
| Conflict | Shown with its owner and a choice to pick another key or replace. Not applied. |
| Free | Source 1 succeeded and nothing matched. |
| Unverified | Source 1 failed or is empty. Applied with a badge. A fallback can add conflicts, but it never turns unknown into free. |

The Keybindings tab turns red with a count while a conflict remains. The picker uses
ordinary buttons and key events. It never uses an editable text control, because Qt's
writable inputs read the clipboard ([finding](../platform-findings.md#known-traps-consolidated)).
Escape cancels capture. Tab leaves capture. Apply is explicit. Hiding the editor,
changing tabs, closing the panel or losing focus stops capture.
