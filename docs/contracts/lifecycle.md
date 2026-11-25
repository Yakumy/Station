<!-- summary: Hiding and restoring Omarchy's own widgets (leases), what a restart keeps, what removal cleans up. -->
<!-- code: lib/bars/Stock* lib/platform/** -->
# Stock widgets, restart and removal

## Stock widgets

`state.stockLease` and `state.displayLease` have the shape
`{ wasEnabled, section, index, disabledByStation }`.

- Settings' Show Omarchy default workspace indicator is `hideNative` inverted, in every
  mode. It shows or hides Omarchy's own installed indicator next to Station's widget;
  Station draws no workspace numbers of its own. Omarchy's indicator numbers each
  monitor in blocks of ten, so it matches Repetitive; in Sync and Non-repetitive it
  shows Omarchy's numbering, not Station's.
- Settings' Show Omarchy Display Icon is `hideDisplay` inverted and defaults to Off.
- The grace-delay control is removed. New configurations use no delay; an existing
  saved `graceMs` remains honored.
- With Show off (the default for both widgets; a saved `hideDisplay: false` stays),
  Station records placement and disables an enabled widget. It records a disabled widget
  as such, and startup and removal never enable that one.
- Restoring happens only for `disabledByStation && wasEnabled`.
- An explicit Show also enables a widget hidden before Station acquired it.
- The workspace widget returns behind Station with `omarchy bar move --after`, falling
  back to its recorded place. `bar put` leaves a present widget where it is, so use
  `bar move`.
- Bar writes rebuild the bar, so Station runs them one at a time.
- Leases retain section and index in all six host sections. Removal validates and
  restores these placements with the same fixed-script argument checks.

## Removal and restart

`Component.onDestruction` fires on disable, removal and shell restart alike. It starts a
detached fixed script with validated positional arguments:

1. Wait, then look for the shell for up to about 15 s.
2. Read `listPlugins`, retrying for up to about 15 s, because the shell drops IPC calls
   while it rebuilds plugins. If it never answers, stop. If it shows Station enabled,
   stop. This is a restart.
3. Otherwise restore only the leased widgets. Each widget command retries, and a widget
   that still fails does not stop the remaining steps.
4. Neutralize the current marked block by changing `disabled = true` to `false` and
   clearing `mirror`, with a backup and an atomic replace. Geometry stays. Single and
   Mirror do not outlive the plugin.
5. Delete Station's `station-workspaces.lua` and `station-color.lua` toggle files.
6. Run `hyprctl reload`, which clears runtime binds and rules and returns every output
   to its own colors. `SUPER + n` must work immediately.

If the shell never answers, the script does nothing, and the user runs `hyprctl reload`.
Preferences, state, backups and wallpaper copies remain.
