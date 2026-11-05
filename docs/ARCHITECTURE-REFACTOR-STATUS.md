# Architecture implementation checkpoint

This checkpoint lets the maintainer or a later coding session resume the approved
[proposal](ARCHITECTURE-REFACTOR-PROPOSAL.md) without reconstructing the chat.

## Authorization and limits

The user authorized implementation and one commit per completed step on `dev`.
Do not push. The initial implementation scope excluded installed updates and live
changes. After M7, the user separately authorized an installed update and tests.
The bounded follow-up below records that execution. Topology/configuration edits,
crash experiments and dependency installation remain outside this test scope.
M4 is committed as `ddceb48`. After the M5 packet review, the user delegated
the decision and instructed continued work. The accepted scope and source SHA
are recorded in the [M5 review packet](ARCHITECTURE-M5-REVIEW.md).
M5 is committed as `8395b1a`. The user separately approved the
[M6 review packet](ARCHITECTURE-M6-REVIEW.md), then instructed continued work.
M6 is committed as `28c7eba`. M7 is committed as `4ffa775`.
M0–M7 implementation is complete, with the M2 deletion deferred. M2 deletion requires
its cross-version and detached-recovery proof. M8 and M9 remain optional.

## Completed work

| Step | Commit / status | Evidence |
| --- | --- | --- |
| Proposal | `b5b946f` | Reviewed audit, compatibility gates and hardware checklist |
| M0 | `07016a1` | 266 Node cases passed, 25 QML components compiled, theme scan 44 files/0 violations, clean-export plugin validation passed |
| M1 | `cce6819` | 267 Node cases passed, 25 QML components compiled, theme scan 45 files/0 violations. Key-picker pointer harness and 23 layout cases passed |

M1 adds `lib/Tabs.js`. Numeric service setters and snapshot values remain
compatible. Feature code names tabs. Keybindings receives explicit activation.
Wallpaper `choose(identity)` crosses the closed bridge allowlist and validates
identities against the observed layout. Picker completion restores Wallpaper on
success, cancellation and error.

Pre-fix F1 characterization remains in M0 commit `07016a1`. Current tests require
corrected behavior without gap exceptions. They execute production function
bodies with external boundaries doubled. They do not prove a running shell's
physical pointer or unmap behavior.

The compile probe reported the existing host-portal registration warning without
compile failures. The offscreen pointer fixtures reported existing paint-double
warnings. No live topology, installation, restart, wallpaper or user configuration
experiment was run. Portable checks need unrestricted subprocess execution on
this machine because the sandbox rejects some Node/Lua fixtures.

M2 compatibility evaluation is committed as `8e4f7cf`. M3 is committed as
`40f0d8b`. M4 is committed as `ddceb48`. M5 is committed as `8395b1a`.

## M3: bar settings owner

`BarSettingsController.qml` owns pending/observed rows, measured limits and its
publication timer. Service keeps 24 forwarding methods and the same detached
snapshot fields. Root config storage, panel intent and compositor effect ownership
remain unchanged. The controller receives finite ports and no Service QObject.

The retained bar scenarios now execute production owner functions through a test
adapter. Three new portable cases check ownership, forwarding and scoped ports.
`python3 tools/v2/check-bar-settings.py` exercises the production QML owner with
fake effects: five behavior cases plus setup/cleanup passed. It checks reactive
preferences, deferred flush, external-row supersession, load gating and failure.
All 274 Node cases passed. All 26 runtime QML components compiled. Theme scan:
46 files, no violations. Plugin validation passed on a clean export with the
current changes overlaid. No installed bar or compositor state changed.

## M4: explicit window-save/readback owner

`WindowSettingsController.qml` owns the appearance FileView/source/load state,
busy flag and both temporal methods. Service retains two forwarding methods,
its command queue, config generation, config merge and shared error field.
The owner receives data and finite ports; no whole Service or shell QObject.
No transaction script, schema, marker, proxy or display-preview behavior changed.

The existing six save/readback outcome scenarios now execute the owner bodies.
Three added Node cases cover forwarding/ownership, an observation started before
an edit, and rejection gates. All 277 Node cases passed (baseline: 274).
Seven before/after save traces matched, including command argv, generation,
busy transitions and final observed/error state.
The new offscreen owner/proxy check passed five behavior cases plus setup/cleanup.
Its FileView, command queue and theme effects are doubled; it verifies Qt binding
and callback order, not real filesystem watching or compositor effects.
The existing slider harness passed two cases plus setup/cleanup; layout passed
23 Qt results. All 27 runtime QML components compiled using real installed imports.
Theme scan: 47 files, no violations. Plugin validation passed from a clean export
with the current milestone files overlaid. Whitespace checks passed.

The injected malformed read intentionally logs an incomplete-settings warning.
Compilation retained the host-portal registration warning. Existing pointer/layout
doubles emitted painting/token warnings without test failures. A sandboxed focused
Node run failed at subprocess fixtures; the unrestricted focused run passed all
15 cases and the unrestricted full suite passed all 277. No dependencies were
installed, no live desktop changes were made and nothing was pushed.

## M5: workspace migration owner

`WorkspaceController.qml` now owns the workspace journal FileView, mapping load
gate, journal/commit phases, revision, retry timer, attempts, focus and topology
flag. Service retains four forwarding methods and detached/read-only projections.
Its event handlers mark topology through an owner method. The preview handler
clears that flag through a second method after the existing fresh snapshot.
No root handler independently writes migration state.

The owner receives data and finite effect ports, not the Service QObject.
Root operation arbitration, queues, configuration generation, expected events,
preview baseline and watchdog remained with Service at M5. M6 transfers their
ownership as recorded below. Preview reconciliation retains
the enclosing generation. Journal preview data and consumer snapshots are detached.
The extraction preserves the existing late-callback policy without adding a token.

All eight migration cases and all 19 display-transaction cases retain their
assertions and now execute production owner bodies through an external-port
adapter. Fifteen added Node cases cover ownership, ten old/new trace comparisons,
both rollback directions, OpenApps identities and detached preview data.
The pinned pre-M5 function/FileView fixture comes from
`ddceb489fe176920ae9f30e861a5f082e0c6a07d`. Effect traces and serialized bytes
match for the same observations. Both implementations load temporary journal
files from the other implementation through their production load handlers. They resume partial moves without
conversion or deletion.

`python3 tools/v2/check-workspace-owner.py` passed eight production QML behavior
cases plus setup/cleanup. It controls FileView signals and fake compositor replies,
but uses the real 500 ms retry timer. Cases include delayed/failed journal and
commit acknowledgments, retry exhaustion, superseding topology, partial restart,
late callbacks and the enclosing preview generation/baseline contract.

`python3 tools/v2/check-workspace-fileview.py` passed with real Quickshell FileView
objects and temporary journals. It checks valid/invalid/missing loads, actual
saved/failed signals, identical-text suppression and revision-based writes.
Python checks the final disk bytes. The real-file fixture starts with a pending
journal and a partially moved client. All dispatch is fake. This does not prove
crash durability, detached watchdog survival or hardware behavior.

All 292 Node cases passed. All 28 runtime QML components compiled. Theme scan:
48 files, no violations. The existing layout harness passed 23 Qt results.
Plugin validation passed from a clean export with the milestone files overlaid.
Whitespace checks passed. Documentation lint added no hard findings in changed
lines. Existing hard findings across the five touched documents decreased from
249 to 243. Compilation retained the host-portal warning. Layout doubles
retained their existing painting/token warnings. The real-file fixture deliberately
logs one failed save and unused graphical-child warnings.
Sandboxed Node execution again failed/stalled at subprocess fixtures. The
unrestricted focused and full runs passed. No dependencies were installed.
No installed plugin, live configuration or topology changed. Nothing was pushed.

M2 plain copies remain. M6 ownership and evidence follow below.

## M6: display transaction owner

The user explicitly approved packet revision 1 against
`8395b1abbc65320a214e83e25269dc5c550d1e36`. The approval and scope remain in the
[M6 packet](ARCHITECTURE-M6-REVIEW.md). Its initial documentation changes were
preserved and are included with this milestone.

`DisplayController.qml` now owns draft/preview state, original baseline, staging,
source/candidate/token FileViews, preview-arm and Keep processes, and countdown.
Service retains 32 forwarding methods, read-only/detached projections, root
operation/configuration generations, both queues and the serial panel barrier.
Workspace recovery, snapshot failure, Mirror role changes and source migration
use explicit methods. No other root handler writes display-private state.
Config publication and saving remain separate effects with owner cleanup and
source reload between them. M2, fixed scripts, eight Keep arguments and native
entry/bridge identities remain unchanged. No new cancellation policy was added.

All 292 earlier Node cases retain their assertions. The existing display harness
is reusable across old/new implementations and still passes its 19 original scenarios.
Twenty-three additional Node cases cover ownership, 18 matching effect/state/byte
traces, startup gates, and rollback in both directions. The exact pre-M6 Service
fixture has SHA-256
`1945107f0eeabb852fd6541591787cd663f832c179c98b6062a2cea21fbf6086`.
Rollback cases use temporary pending journals, tokens and interrupted candidates.
They preserve personal source bytes and the retained plain copy.

`python3 tools/v2/check-display-owner.py` passed 19 behavior rows plus setup/cleanup.
It uses the production Display/Workspace owners and Service composition, read-only
projections and panel-barrier functions. I/O signals, processes and compositor
execution are doubled. It covers both Mirror directions, migrate-first ordering,
re-edits/new clients, partial restart, candidate order/identical text, failures,
stale generations, running callbacks, observation cancellation and source readiness.

`python3 tools/v2/check-display-fileview.py` passed with real FileViews and watching.
All paths and runtime logs are temporary. Process/StdioCollector are doubled by
qualified imports in the temporary owner copy. No transaction command executes.
It checks source edits, actual candidate save/failure signals, identical retries
and final disk bytes. Source bytes survive and no plain-copy commit occurs.
This is not crash durability, detached watchdog survival or hardware evidence.

The full portable suite passed 315 cases. All 29 runtime QML components compiled.
Theme scan: 49 files, no violations. Layout passed 23 Qt results after adapting
its source extraction to the production owner. The unchanged workspace Qt harness
passed eight cases plus setup/cleanup. Clean-export package validation passed.
Document links, anchors and fences resolve. Prose checks added no hard findings
in changed lines. Final whitespace checks passed. The compiler retains its
host-portal warning. Existing layout paint doubles log their usual warnings. The real-file
fixture logs its deliberately failed candidate write and graphical-child warnings.

Initial broad checks identified source-extraction fixtures that still referenced
moved root bodies. They now exercise owner bodies or guards without losing assertions.
The new precedence trace also needed its fake monitor path. These fixture failures
were corrected before acceptance. No dependencies, installation, restart, live
configuration/topology change or push occurred. M7 evidence follows below.

## M7: panel session and local editors

`PanelSession.qml` owns widget-local screen retention, stable bar edge, tab
restoration, reopen retries, evacuation probing and the acknowledgment timer.
Service still owns persistent panel intent and the serial/output safety barrier.
StationPanel keeps the top-level bridge reader, service selection and polling.
It forwards host close methods and composes the same KeyboardPanel and viewport.
The bridge import remains in `Panel.qml` beside Service.

The session receives a finite intent facade, host capabilities and callbacks.
Its availability callback reads service presence synchronously. This avoids a
second property's notification order during service resolution. Root service
changes invoke session restoration at the original event boundary. Deferred
settlement still captures the persistent direct service or bridge API, host bar
and scalar deadline. It never captures the widget-owned facade or proxy.

`DisplayControls.qml` owns brightness reads, captured connectors, the 180 ms
debounce, pending write and text-size queue. Its Process objects retain the
original argv, callbacks and panel lifetime. KeybindingsTab owns its modifier/key
draft and edit functions. All six tabs receive common read-only tokens and
explicit feature inputs/actions. Their finite service facades forward synchronous
results on both paths. Wallpaper receives its existing controller/proxy surface
and a dismiss callback. No tab receives StationPanel through `panelRoot`.

All 315 earlier Node cases retain their behavior assertions. Sixteen added cases
check ownership, 13 old/new effect comparisons, unchanged geometry/I/O algorithms
and forwarding arguments/results. The reference is the exact panel from `28c7eba`.
Its SHA-256 is
`1b12e5a192e1e97c77ed4f4ca9647f9bb4f62b5078c4df28b0f928cae259072c`.
The service intent format and bridge allowlist remain compatible with rollback.

The offscreen session harness passed 13 behavior cases plus setup/cleanup.
It runs production helpers, key picker/tab and composition facades with fake I/O.
Real timers and notifications exercise late service resolution, tab/output restore,
cross-axis geometry, peer popouts, serial acknowledgment, connector races, text
queuing and teardown. The existing geometry self-invalidation and implicit
`exitCode` warnings are specifically expected. Source equality checks pin those
unchanged algorithms. All other warnings fail this harness.

The populated-panel integration check passed with installed host components,
fake observations and inert Process transports. It instantiates all six tabs
through both direct and bridge paths, then checks intent, tab writes, key edits
and explicit dismissal. The separate panel-size check passed fixed dimensions,
overflow, scroll reset and the short viewport. Neither proves physical unmapping
or real hardware behavior. The integration fixture uses a service-shaped QObject,
not production Service. It primes the bridge before changing service paths.
Late and absent service behavior is covered separately by the offscreen harness.

The full portable suite passed 331 cases. All 31 runtime QML components compiled.
Theme scanning covered 51 files with no violations. Pointer/layout checks passed 23 Qt results. Window sliders passed
four results, and the key picker passed 14. Clean-export plugin validation and
whitespace checks passed. Prose lint retained the same 236 pre-existing hard
findings across the four affected documents. New prose added no hard findings.
The compile and isolated previews retain the host-portal warning.
M2 persistence, Service, fixed transaction scripts and live state remain unchanged.
No dependency installation, plugin update, desktop restart or push occurred.

M8/M9 remain optional and have not started. File moves alone do not demonstrate
a maintenance benefit. No recurring navigation problem or verified stock-bar
extraction benefit was established by this milestone. Do not extend this work
into those optional changes without that evidence.

## Post-M7: optional review and installed smoke check

The user authorized continued work and allowed installed updates for verification
on 2026-11-05. Source and installed checkouts were clean on `dev` before updating.
The installed origin was `file:///home/aryan/hdd/Programming/station`.
The stock updater advanced installed code from `d9caad9` to
`4ffa775882454306916f090ebed8c4f5d27b0f65`. Source and installed revisions then
matched. All 178 tracked file paths had matching bytes. One required shell
restart followed the update. Shell ping returned `ok`. Quickshell reported new
process 259084, launched at 08:41:56 local time.

Private baseline snapshots and recovery copies remain under
`/tmp/station-installed-m7-xw3mm3q7`. They include Station status, monitors,
clients, workspaces, layers, autoreload and relevant persisted files. Station was
idle before and after, with no pending migration, preview or layout error.
The committed output order remained `HDMI-A-2`, `eDP-1`.

Three live IPC open/close cycles used the installed Station panel on `HDMI-A-2`.
Each open mapped two keyboard-panel surfaces and published wanted intent.
Each close removed both surfaces and cleared intent. Observed open latency was
148–180 ms. Observed close/unmap latency was 245–260 ms. These include polling
and IPC overhead. The panel finished closed. This checks actual layer presence,
but does not establish evacuation acknowledgment ordering during monitor removal.

Both existing clients retained their identities, monitor and workspace. Display
geometry, active workspaces, Station number, per-monitor bar rows, appearance,
leases and autoreload matched the baseline. Config errors remained empty.
All 36 binding definitions and classifications matched, and 36 unique Station
bindings were registered. Stock-owner label observations became empty after the
running service had replaced those bindings. The classification logic is unchanged.
No physical keypress test was performed.

Two automatic persistence changes occurred. Journal revision advanced from
2685 to 2689 with the same committed map and no pending entry. Shell
`bar.position` changed from `right` to `left`. The existing focused-menu sync
mirrors the focused output's saved edge while preserving independent bar rows.
No display or window setting was edited. Monitor/appearance source files,
Station preferences, state data and the retained M2 plain copy kept their bytes.
The runtime log retained the known bar-edge binding warning and implicit
`exitCode` warning. It contained no TypeError, ReferenceError or assignment error.

This is partial H10 evidence for an ordinary restart and a panel smoke check.
Disable/remove, destructive topology transitions, watchdog crash recovery,
physical keys and three/four-output hardware were not tested. H1–H9 and H11
remain open for their individually scoped hardware checks. The current full-bar
bridge path was exercised live. The trusted direct path retains isolated evidence.

The bounded M8 review traced M3, M4 and M7 through their owners and callers.
M3 touched 10 files, M4 touched 11, and M7 touched 35. Directory moves would
retain those composition/contract callers and add import/tool path changes.
The six extracted owners are already discoverable by one filename search.
This review established no recurring owner-location failure or reduced caller
count that justifies the move risk. M8 remains deferred.

The bounded M9 review examined MonitorBar's zoom/rescan hooks and recent fixes.
Its loader hooks already converge on one slot-local scheduler and implementation.
No upstream-update or teardown defect was reproduced. Extracting that code would
still require its active-item, zoom and widget-rebuild notifications. No measured
reduction in private caller knowledge was established. M9 remains deferred.
A future candidate needs concrete benefit evidence and separate authorization.

This checkpoint commit adds documentation only after the installed smoke check.
Installed/running production code remains the tested `4ffa775` revision.
Nothing was pushed. M2 persistence remains intact.

## M2: retain plain-copy persistence

Deletion is deferred. The pinned pre-v3 cleanup at
`86f6cf4bc488e5217af2a0a8fe72673b528a4e6b` consumes the plain copy.
The exact payload is retained in `test/v2/fixtures/legacy-plain-cleanup.sh`.
Its SHA-256 is `2f0516178852c2a63a92c8746725c39fa55c89b8a787de8b3a7aaffaa596c00f`.

Four isolated compatibility cases passed. They demonstrate two deletion hazards:
legacy cleanup leaves disable/mirror rules intact without the copy, and an old
copy can restore stale geometry. Both payload generations skip an enabled shell
restart. Current cleanup neutralizes current rules without the copy.

These cases use the real payloads with temporary paths and fake desktop commands.
They skip elapsed sleep time. They do not prove the complete supported-version,
watchdog, interrupted-Keep or code-rollback matrix. No support window was narrowed.
Production writers, FileViews, argument contracts and retained user files remain
unchanged. A future deletion requires the full proof and human review in M2.
M3 and M4 do not depend on that deletion.

## Resume procedure

1. Read `AGENTS.md`, the proposal and this checkpoint.
2. Check `git status --short --branch` and `git log -5 --oneline`.
3. Preserve any work outside the next milestone.
4. Read the completed M5–M7 evidence before any optional follow-up work.
5. Keep M2 persistence intact. M8/M9 remain optional and require demonstrated benefits.
6. Update this checkpoint and affected architecture/contracts with each step.
7. Inspect the complete and staged diff. Commit that step on `dev`. Do not push.

The installed plugin remains separate from this source checkout. A local commit
is not evidence that the running shell loaded it.
