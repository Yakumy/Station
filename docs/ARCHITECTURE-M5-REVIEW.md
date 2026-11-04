# M5 review packet: workspace migration owner

Packet revision: 1. Status: awaiting explicit human approval. This packet is part
of the M4 commit; use that commit's full SHA as the candidate review revision.
The migration implementation was inspected at
`40f0d8b38527317d164b56f42b18e1d0f59b768b`; M4 changes only window-setting ownership,
tests and documents. No M5 production changes have been made.

The [proposal](ARCHITECTURE-REFACTOR-PROPOSAL.md#mandatory-human-review-checkpoints-before-m5-and-m6)
requires this review before implementation. General delegation does not approve
M5. Record the approved source SHA, packet revision, conditions and authorization
here when approval arrives. A material change to these boundaries reopens review.
M6 and hardware execution require separate approvals.

## Concrete transfer

Create one `lib/WorkspaceController.qml` child of the persistent Service. Leave
`Grid.js`, `Hypr.js`, fixed recovery/transaction scripts and journal formats intact.
Keep the existing `lib` import location; do not reorganize directories.

| Transfer from Service | Proposed owner contract |
| --- | --- |
| `workspaceData`, `mappingLoaded`, `migrationPhase`, `topologyDirty`, `migrationAttempts`, `migrationFocus`, `migrationCommit` | Controller is their only writable owner. Service exposes read-only compatibility projections. `workspaceMap` remains derived from committed `workspaceData.mapping` |
| `reconcile`, `migrationFailed`, `migrationSaved`, `executeMigration` | Move complete function groups. Preserve Service forwarding methods wherever existing callers/tests use them |
| `workspaceFile` FileView | Move initial validation/load, pending/preview recovery, atomic writes, saved/failure handlers together. Keep the exact `workspace-map.json` path and JSON shape |
| `migrationRetry` Timer | Move with owner, retain 500 ms delay and three retry scheduling attempts |
| `ensureDirs` call to `workspaceFile.reload()` | Service calls owner `reload()` after directory readiness; do not change other FileView startup ordering |

State deliberately retained by Service:

- `state`, `gen`, `queuedStation`, compositor event expectations and action queue.
- `clients`, monitor/assignment inputs, current station and persistent state file.
- Display preview intent, `previewBaseline`, evacuation serials, source/candidates,
  watchdog/token, Keep/Revert and `finishPreviewApply`.
- Window actions, binds, panel intent and OpenApps lifecycle.

`previewBaseline` stays with display preview until M6. The workspace journal
contains its serialized snapshot; it must never mutate the input baseline or
replace its original identities during re-edit. On journal load, the owner asks
Service to restore the recovered preview baseline. On ordinary migration commit,
it asks Service to clear that baseline at the existing point. Keep success still
clears the root baseline through its existing path. There must be no second
writable preview owner and no mutable journal exposed over the bar bridge.

## Data and effect surface

Use explicit bindings and finite callback ports, following M3/M4. Do not pass the
whole Service QObject. The proposed surface is bounded as follows:

| Direction | Data or port | Responsibility |
| --- | --- | --- |
| In | `stateDir`, operation state, root operation generation, removal-grace flag | Paths and arbitration context; owner does not create a second operation generation |
| In | clients, lanes, current station, legacy-grid flag, preview baseline, panel screen, current layout error | Read-only inputs required by the existing four bodies |
| In | `targetMapping()` | Evaluate the current root-derived mapping after refreshed inputs; do not capture a stale target across an asynchronous refresh |
| In | `refresh(includeClients, done)`, `updateAssignments()`, `focusedClient()` | Existing compositor observation and assignment operations, unchanged ordering |
| In | `beginMigration()` and `setOperationState(value)` | Root starts an ordinary migration or receives the existing state transition; preview reconciliation reuses its enclosing operation |
| In | `evalLua(lua, done)`, `recordExpectedEvents(value)` | Existing validated dispatch queue and pre-dispatch expected-event publication |
| In | `reportError(message)`, `setCurrentStation(station)` | Existing shared error and station updates, including current timing before commit acknowledgment |
| In | `commitMigrationState(station)` | Clear legacy-grid flag, set persisted last station, save root state at existing commit-ack point |
| In | `restorePreviewBaseline(value)`, `finishPreviewApply()`, `failPreview(message)` | Restore/clear baseline, settle enclosing preview, or execute existing exhausted-retry Revert path |
| In | `focusStatements(station, output)`, `showStation(station)`, `ready()` | Existing focus/show and startup-ready callbacks; `ready()` calls `maybeStart()` |
| Out | read-only committed map, detached/read-only pending journal data, mapping-loaded and migration-phase projections | Existing consumers continue to use the same root names; OpenApps receives committed map plus pending identities |
| Methods | `reconcile()`, `reload()`; compatibility forwarding for saved/failure/execute if required by retained tests | No new UI actions, IPC methods, schemas or public return values |

This extraction needs more ports than M4 because it coordinates root arbitration
and display preview. Keep these ports specific. If implementation needs access to
other root state, stop and revise the packet instead of passing `station: root`.
No cancellation/token policy is silently added: current migration callbacks are
serialized by the journal/phase protocol; root configuration-generation checks
remain on the existing command queue. Tests must expose interleavings before any
proposed change to that policy.

## Current and proposed phase traces

These are executable isolated-test observations and required after-extraction
traces, not physical compositor evidence. “Ack” means FileView `saved`.

```text
Ordinary: root begin(migrating), gen increments once
  -> refresh clients -> assignments -> current target -> plan/resume identities
  -> journal revision +1, old mapping + pending + original preview, phase=journal
  -> write -> ACK -> phase=moving
  -> publish expected events -> rules batch -> move batch -> fresh client snapshot
  -> verify current target and destinations
  -> stage commit revision +1, phase=commit -> write -> ACK
  -> publish new mapping, clear pending/phase/retry count -> save root state
  -> idle -> replan if topology changed, otherwise show station and restore focus

Preview: reuse root preview state and gen; do not call begin(migrating)
  -> same journal/move/verify/commit barriers
  -> retain original preview baseline and root preview token
  -> replan if needed, otherwise focus and finishPreviewApply; remain previewing

Journal-save failure: no moves; retain pending and old map -> retry
Move failure: fresh verification decides success; failed destinations retain journal
Commit-save failure: moved clients retain journal identities and old published map
  -> retry from identities, never reinterpret partially moved workspace numbers
Topology change during movement: keep identity journal -> refresh/replan -> new ack
Restart after partial movement: load old mapping + journal identities + preview
  -> resume by client identity and station -> new revision and ack -> convergence
```

The proposed controller must produce these same traces and serialized journal
bytes for the same observations. Real FileView suppresses `saved` for identical
text: preserve the revision increment, and add a real temporary-file harness
before accepting an extraction. Never synthesize a successful ack to unblock it.

## Evidence and tests required for acceptance

M4's complete portable run passed 277 cases. In that run, the eight cases in
`test/v2/migration-service.test.cjs` passed and directly exercised the four
production migration bodies. They cover:

1. Journal acknowledgment before moves; commit acknowledgment before map publication.
2. Failed journal writes and failed moves retain recovery state.
3. Aggregate false dispatch after verified moves can still commit.
4. Restart after a partial expansion resumes saved per-window destinations.
5. Zero-output intervals and removal grace preserve the mapping.
6. Failed commit acknowledgment retains identities and old numbering through retry.
7. Nested preview retains generation 42 and the original baseline through commit.
8. Identical retry plans serialize distinct revisions to obtain a new acknowledgment.

`test/v2/grid.test.cjs` additionally covers every one/two/three-output transition,
identity-based resume after a further topology change, pinned/named/special and
unmanaged exclusions. `test/v2/display-transaction.test.cjs` covers re-edits,
restart recovery, timeout, Single survivor preparation and panel evacuation.
These are doubles and source-body tests; they do not prove real signal delivery,
disk persistence, monitor ordering or a detached process surviving shell death.

Before accepting M5:

- Preserve every current assertion. Adapt fixtures to the owner rather than
  replacing behavioral tests with forwarding/source checks.
- Add production QML-owner coverage for delayed/failed journal and commit acks,
  retry exhaustion, superseding topology, a partially moved restart, stale callback
  interleavings, and the nested preview baseline/token contract.
- Use a real Quickshell FileView only with a temporary directory and fake dispatch.
  Verify initial load/failure, actual saved/failed signals and identical-write
  behavior; never read or write the installed journal.
- Compare before/after effect traces and serialized journal bytes. Read-only
  snapshots must not publish a committed target before its ack. Confirm OpenApps
  remains identity-aware during movement.
- Run the full portable suite, recursive QML compiler, theme checks, offscreen
  regression checks affected by the change and clean-export plugin validation.
- Stop on unexplained trace differences, lost coverage or recovery ambiguity.

## Rollback, compatibility and hardware limits

Rollback is a normal code revert of the M5 extraction; keep the on-disk journal
schema and revision semantics unchanged so the previous code resumes it. Prove
both directions with temporary journal fixtures: old journal -> new owner, and
new-owner journal -> pre-M5 functions after partial movement. No resetting or
removing `workspace-map.json` and no user data conversion is authorized.

M2 deletion remains deferred. Retain every plain-copy writer, argument contract
and cleanup payload. The M2 compatibility hazards are unrelated to moving this
owner and cannot be used to justify narrowing old-version support here.

Use the proposal's reproducible hardware procedure for later authorized runs:
H6 (long/short hotplug grace and identity migration), H7 (re-edit/new windows,
Revert and external change during preview), H9 (explicitly approved shell crash,
detached watchdog and journal recovery). Capture pre/post window identities,
config bytes, journal phases, token age and compositor errors, then restore the
original desktop state. H9 is distinct from a normal shell restart. No such run
is authorized or claimed in this packet. Three/four-output, simultaneous dock,
lid/suspend/cold-login paths remain unverified hardware limits.

Approval decision required: accept this transfer/port scope and temporary-file
verification strategy, with M2 retained and live tests excluded. Record any added
conditions before M5 begins. M5 approval does not approve M6.
