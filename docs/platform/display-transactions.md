<!-- summary: Crashes and repairs in preview, Keep, reload-safe persistence and cold-start geometry. -->
<!-- code: lib/displays/Display* lib/platform/Transactions.js -->
# Display preview and Keep investigations

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Preview restoration and shell reload observations (2026-10-05)

- Station suppresses `configreloaded` while applying a display layout. Therefore
  its own Revert must explicitly refresh the compositor snapshot, rebuild the
  display draft, and invalidate/reapply runtime bindings. Refreshing monitor data
  alone leaves the canvas and mode selector showing the discarded preview.
- A Quickshell SIGSEGV at 18:01:04 followed repeated local-plugin reloads and a
  restart request. The core stack includes `__dynamic_cast` and QML object
  finalization/incubation; it does not identify a Station QML callback as the
  cause. The shell automatically recovered. Omarchy's launch script separately
  documents restart crashes after reloading partially written trees. Updating
  the local checkout while the shell is stopped avoids that reload sequence;
  this is a precaution, not proof of the crash's root cause.

## Display transaction repair (2026-10-08)

- **[SRC][QTTEST]** The monitor-card Off handler called `setDisplayValue()` and
  then `previewLayout()` on its own delegate. Publishing the new Repeater model
  destroys that delegate before the second call. The service now owns both steps
  in `setDisplayEnabled()`. The production QML handler is exercised by
  `test/qml/layout.py`, including destruction during the Off action.
- **[SRC]** Preview migration was explicitly blocked by `reconcile()`. Single
  disabled the other output but did not compact/merge its stations until Keep.
  Preview now uses its own effective mode for journaled migration, retains a
  durable per-window baseline, and starts the countdown after migration. Revert
  and restart recovery restore the original station/output assignments.
- **[LIVE][SRC]** During the user's Keep attempts at 00:19:34, 00:20:01 and
  00:21:15 local, the Quickshell event log showed HDMI added/removed/re-added
  during reload. The saved monitor block contained Single on eDP-1, while
  Station's config and live mapping remained Extend. Hyprland `configerrors`
  was empty. `monitoradded` could call `updateAssignments()` while
  `applyingLayout`, reset the draft from old config, and reapply that old mode.
  Keep now captures accepted options and defers event-driven runtime changes
  until a fresh post-transaction snapshot. Candidate saves are acknowledged
  before launching the filesystem transaction.
- **[SRC]** The "Other monitor rules also mention" text was a nonfatal warning
  stored in the error field. Older geometry rules above Station's final managed
  block do not by themselves invalidate it. Keep no longer reports those
  mentions as an error or removes the user's earlier rules.
- **[SRC]** An existing widget on the surviving output was never told to reopen:
  restoration only ran on construction/service binding. The service now chooses
  a usable destination, and existing panels observe transfer/screen changes.
  A still-open copy on the output being disabled cannot block the hand-off.
- **Verification:** `test/unit/display-transaction.test.cjs` executes production
  service functions with queued compositor events and disk acknowledgments. It
  covers immediate migration, Keep reload races, repeated mode previews,
  timeout, Revert, restart recovery, enabling a Single-mode disabled output,
  and candidate-write failure. These tests do not simulate GPU/Wayland internals.
- **[LIVE] Installed repair `103a6de`:** a Single-on-eDP-1 preview moved all
  eight eligible windows to their compact single-display station IDs. A panel
  opened on HDMI-A-2 transferred to eDP-1; `hyprctl layers -j` confirmed the
  visible keyboard-panel surface there, with 12 seconds remaining. Revert
  restored every checked window's original workspace and physical monitor.
- **[LIVE] Keep:** repeating that Single preview and pressing Keep persisted
  `single`/`eDP-1`, retained the single-output map, and produced no layout error.
  The verification then saved Extend and restored original window ownership,
  monitor geometry, focus, and the initially closed panel state. This also
  repaired the earlier saved-block/config mismatch. A subsequent Mirror
  preview migrated all seven then-present eligible windows and passed Revert.
- **[LIVE] Final state:** idle, saved/draft mode Extend, two-output workspace
  map, no pending migration, empty layout error, and empty Hyprland
  `configerrors`. No crash or zero-output warning appeared during these checks.
  Temporary snapshots: `/tmp/station-display-live-FZjoI9` (Single/Revert),
  `/tmp/station-display-live-qozfEr` (Single/Keep/restoration), and
  `/tmp/station-display-live-rCG0QJ` (Mirror/Revert). These contain local window
  metadata and are not committed. The automated suite (16 test files), 16 Qt
  layout tests, and installed-component QML compilation also passed.

## Keep-triggered Zen crash and reload-safe persistence (2026-10-08)

- **[LIVE]** The decisive reproduction was asymmetric: selecting Single on
  either output completed window migration and left Zen working; Zen crashed
  only when the user pressed Keep. Two Zen cores (PIDs 34794 and 256628) had
  the same GTK Wayland stack: `xdg_output_handle_name` called `g_free()` on an
  already-freed monitor object while processing output-name payloads for
  `HDMI-A-2`/`eDP-1`. This is a GTK/Zen use-after-free, but Station's redundant
  reload/output reannouncement was the controllable trigger. There was no OOM,
  GPU reset, simultaneous Hyprland core, or Quickshell death in these events.
- **[SRC]** Preview already avoided this trigger: `modeOnlyRules()` deliberately
  emits no geometry, and applies only changed enable/disable/mirror state. Keep
  instead saved a managed block containing one geometry-only declaration per
  output followed by separate state declarations, forced `hyprctl reload`, and
  replayed runtime monitor state once more after its snapshot. That made Keep a
  new topology transaction instead of acceptance of the working preview.
- **[DOC][SRC]** `hl.get_monitors()` exposes enabled monitors, not the disabled
  set returned by `hyprctl monitors all`. A guard on each output being disabled
  therefore skips exactly the output that must remain disabled. Persisted
  layouts now guard the whole operation on an intended survivor and emit one
  combined geometry plus final-state rule for every output inside that block.
  Active/source rules remain first, so Single and Mirror cannot remove the last
  real unmirrored output while changing modes.
- **[SRC]** Successful Keep no longer forces an additional reload after the
  watched atomic file replacement, nor calls `applyRuntime()` after completion.
  It refreshes assignments, commits the accepted migration journal, and restores
  bindings. Error rollback still restores the backup and explicitly reloads it.
- **Verification:** all 16 Node test files and all 16 offscreen layout tests
  pass. The transaction harness models geometry-only rules enabling an output
  during reload and now covers both Single targets. For each, Keep applies one
  final rule per output and produces no additional simulated
  `monitoradded`/`monitorremoved` event. This is source/isolation verification;
  a physical Single → Keep run with Zen open remains required.
- **[LIVE] Follow-up:** Single on `eDP-1` with Zen initially on HDMI succeeded
  through Keep. Switching the already-saved Single layout from `eDP-1` to
  `HDMI-A-2` then failed before preview confirmation: Station enabled HDMI, its
  focus command failed, and Zen PID 292968 crashed at 11:38:47. The core has the
  same GTK Wayland `free()` stack as the earlier pair. Hyprland's DRM log shows
  HDMI changing `false -> true -> false`; the saved Single-eDP rule reclaimed
  the newly added output before the state-only activation could focus it.
- **[SRC]** A disabled Single destination now receives a full geometry plus
  enabled rule, rather than a state-only rule that can lose to persisted monitor
  configuration. This transition is staged differently from Extend-to-Single:
  enable the destination, focus it, migrate clients while both outputs still
  exist, and only then apply the final rules that disable the old output. The
  transaction test starts from saved Single-eDP state and requires the first
  workspace migration to HDMI to precede eDP removal. Physical verification of
  this repaired direction remains required.

## Cold-start geometry regression (2026-10-10)

- **[SRC]** The October 8 combined-rule repair moved geometry inside the
  survivor guard as well as disable/mirror state. With the already documented
  empty cold-start discovery ([Cold start](hyprland-config.md#cold-start-and-boot)), it emitted no saved geometry. The inspected
  user fallback selected scale 2 and automatic placement; the saved block
  selected scale 1 and an external display above the laptop. An isolated Lua
  evaluation of that actual file emitted only the fallback at cold start and
  both saved rules with warm discovery.
- **[SRC]** `Service.applyRuntime()` restores mode/enablement, not saved
  geometry. Shell logs showed startup within seconds, so there is no deliberate
  one-minute geometry recovery timer. A later reload evaluates the guard with
  monitors present. Saved-file backups show additional display writes around
  one minute after login, including external scale 4, then scale 1 and restored
  vertical placement; the initiating user action was not established.
- **[SRC]** The generator now emits an exclusive `else` branch with saved
  geometry and explicit enabled/unmirrored state when the survivor is unknown
  or absent. Single/Mirror still defer restrictive state until discovery. Warm
  reload retains one combined rule per output, preserving the [Keep repair](#keep-triggered-zen-crash-and-reload-safe-persistence-2026-10-08).
- **Verification:** the generator tests execute real Lua with mocked discovery
  for empty, missing, throwing and malformed results; missing saved survivors;
  and warm Extend, Off, both Single targets and Mirror. The transaction harness
  now evaluates Lua branches before applying monitor declarations, rather than
  treating every declaration in the source as executed. This is isolated
  verification, not a new physical reboot or Single/Mirror hardware test.
- **[INFER]** The temporary scale 2 explains the reported enlarged startup
  cursor; the installed defaults still set cursor size 24. No separate cursor
  defect has been demonstrated.
