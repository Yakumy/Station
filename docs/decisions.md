# Decisions

Each entry records a choice that a later review might otherwise reopen, with its
reason. Change an entry only with new evidence, and update it in the same commit.

## One persistent service, no extra process

Station runs inside the shell. It has one service, pure policy scripts and fixed shell
templates. A store library, message bus or daemon adds complexity and solves no
observed problem. Owners coordinate through Service, which is the one operation
arbiter. Separate mini-services would compete for compositor effects.

## System settings are observed, not enforced

Hyprland and Omarchy are the authority for display and window settings. Station used
to restore cached settings on reload, which overwrote changes made elsewhere and
caused flicker. Since 3.0, Station observes effective state and writes only after an
explicit edit. Personal rules later in Lua order win on reload. See
[System authority](contracts.md#system-authority).

## Marked sections at the beginning of files

Station's blocks come first in `monitors.lua` and `looknfeel.lua`, so personal Lua
keeps final precedence under Hyprland's normal rules.

## Window sliders save without a full reload

The original 3.0 path renamed `looknfeel.lua`, which forced a reload, then waited one
second. That caused focus and cursor side effects. The current path suspends
autoreload, saves, and applies only the edited setting. [LIVE] It took about 70 ms and
produced no `configreloaded` event.

## Feature folders with one qualifier each

`lib/` was flat, with 50 files mixing policy, owners and tabs. Folders put a feature's
parts side by side. Each folder has its own QML qualifier because Quickshell's loader
does not reliably resolve one qualifier shared across directory imports. The failure
appears only under the real loader, so `test/run.py all` includes the compile check.

## Keep the adapted bar whole

`MonitorBar.qml` is about 2,450 lines, but it is an attributed adaptation of Omarchy's
bar. Staying close to upstream is what makes later upgrades reviewable. A review of
its zoom and rescan hooks found no defect and no reduction in caller knowledge from
extracting them. Do not split it for size alone. Reopen this with a concrete upstream
update problem or a teardown defect. Station also does not inherit from the host's
private bar type, because that type has no stable extension API.

## Keep the plain geometry copy

Keep still writes `monitors-block.plain.lua`, and no current code reads it. Do not
delete this path yet. A cleanup script from an older Station can still consume it, and
`test/unit/plain-copy-compatibility.test.cjs` shows two hazards: older cleanup leaves
disable and mirror rules in place without the copy, and an old copy can restore stale
geometry. Deletion requires proof across supported versions, the watchdog,
interrupted Keep and code rollback, plus human review.

## Tests compare against behavior, not old source

During the refactor, tests compared current code with pinned copies of old source.
That proved each extraction. The pinned copies were removed afterward, because they
would block any intentional change. Their scenarios remain as behavior checks.
`legacy-plain-cleanup.sh` stays because it guards a real compatibility contract.

## One documentation set

Version folders made readers work out which document superseded which. The documents
now describe current behavior only, and Git keeps the history.

## Features left out of the original specification

The original specification asked for these two. The maintainer declined them on
2026-11-05, so they are not gaps.

- The panel does not open when a monitor connects.
- A fourth output is reported only through `status`. The panel shows no message.

A `removeStationBlock` method that no control called was deleted for the same reason.
Plugin removal has its own cleanup.

## Watch the theme instead of polling it

A 250 ms poll cost about 2% of one core and 57,600 processes an hour on the test laptop.
`inotify-tools` is in Omarchy's base packages. Omarchy's `theme-set` hook was rejected: it
would write outside the plugin, runs only after slow app updates, and misses
`omarchy theme bg set`.

## Panel controls end with their panel

Brightness and text-size requests live in the panel. A request pending when a bar rebuild
destroys the panel is lost, and the user moves the slider again. Moving them into the
service would add code to prevent a rare, harmless result.

## Historical records

These records were removed from the tree. Read them with
`git show 0671e58:<path>`.

| Path at `0671e58` | Content |
| --- | --- |
| `docs/v2/SPEC.md` | The original build specification and its milestones |
| `docs/v3/SYSTEM-AUTHORITY.md` | The 3.0 revision and its evidence |
| `docs/v2/M0.md`, `docs/v2/M0-evidence.json` | The platform gate, with hashes and latency samples |
| `docs/v2/COLD-LOGIN-CHECK.md` | The cold-login experiment |
| `docs/TEST-RESULTS.md` | Dated test results up to 2026-11-04 |
| `docs/ARCHITECTURE-REFACTOR-PROPOSAL.md`, `-STATUS.md` | The architecture audit and milestone checkpoint |
| `docs/ARCHITECTURE-M5-REVIEW.md`, `-M6-REVIEW.md` | Review packets for the two highest-risk extractions |

## Open questions

None. The remaining unverified hardware is listed in
[Coverage gaps](testing.md#coverage-gaps).
