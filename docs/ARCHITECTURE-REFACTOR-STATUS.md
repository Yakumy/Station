# Architecture implementation checkpoint

This checkpoint lets the maintainer or a later coding session resume the approved
[proposal](ARCHITECTURE-REFACTOR-PROPOSAL.md) without reconstructing the chat.

## Authorization and limits

The user authorized implementation and one commit per completed step on `dev`.
Do not push. Do not install an update or change the running desktop under this
scope. M4 is committed as `ddceb48`. After the M5 packet review, the user delegated
the decision and instructed continued work. The accepted scope and source SHA
are recorded in the [M5 review packet](ARCHITECTURE-M5-REVIEW.md).
M5 is completed in this checkpoint revision. Stop before M6 implementation.
Prepare its separate review packet and obtain approval first. M2 deletion requires
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
`40f0d8b`. M4 is committed as `ddceb48`. M5 is completed in this checkpoint revision.

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
preview baseline and watchdog remain with Service. Preview reconciliation retains
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

M2 plain copies remain. M6 implementation has not started and needs its own
review packet and approval.

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
4. Review the completed M5 evidence and prepare the separate M6 review packet.
5. Keep M2 persistence intact. Obtain explicit M6 approval before implementation.
6. Update this checkpoint and affected architecture/contracts with each step.
7. Inspect the complete and staged diff. Commit that step on `dev`. Do not push.

The installed plugin remains separate from this source checkout. A local commit
is not evidence that the running shell loaded it.
