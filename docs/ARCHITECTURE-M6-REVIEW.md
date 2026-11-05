# M6 review packet: display transaction owner

Packet revision: 1. Status: implemented. See the [checkpoint](ARCHITECTURE-REFACTOR-STATUS.md#m6-display-transaction-owner).
Reviewed source: `8395b1abbc65320a214e83e25269dc5c550d1e36` on `dev`.
The worktree was clean before this documentation task. M6 production work had
not started when this packet was reviewed. Approval is recorded below.

The [proposal](ARCHITECTURE-REFACTOR-PROPOSAL.md#mandatory-human-review-checkpoints-before-m5-and-m6)
requires a separate M6 decision after M5. The user's instruction to start the
next task starts this review step. Record the approved revision, conditions and
authorization here before implementation. A material boundary change reopens review.

Approval recorded 2026-11-05 against the reviewed source above. After the packet
and scope summary, the user explicitly instructed: “approved, keep going”.
This approves the proposed behavior-preserving M6 transfer, isolated verification,
documentation and one completed-milestone commit on `dev`. M2 remains retained.
No push, installation, restart, live configuration/topology change or dependency
installation is authorized. A material scope change reopens review.

## Prerequisites and evidence limits

M5 is committed at the reviewed source SHA above. Its
[checkpoint](ARCHITECTURE-REFACTOR-STATUS.md#m5-workspace-migration-owner) records:

- 292 passing Node cases and 28 compiled runtime QML components.
- Eight production workspace-owner Qt cases, plus setup and cleanup.
- Real FileView signals and disk bytes tested with temporary journals and fake dispatch.
- Ten matching pre-M5/owner effect traces and serialized journals.
- Journal rollback in both directions after partial movement.
- Passing layout, theme and clean-export package checks.

These are M5 results, not new M6 test results. The initial packet used source inspection.
No runtime suite or hardware experiment was repeated for that initial review.
The checkpoint records subsequent M6 verification.
M5 evidence does not prove panel unmapping, crash survival or hardware behavior.

M2 deletion remains deferred. Retain both candidate FileViews, both readiness
flags, plain-copy paths, all eight Keep arguments and the legacy cleanup fixture.
Keep the existing plain writer even though current cleanup does not consume it.
Do not delete or convert any user file.

The [v3 authority contract](v3/SYSTEM-AUTHORITY.md) remains authoritative.
Observe shared settings. Persist only explicit edits. Personal Lua retains final
precedence. Keep the direct window-save owner and its no-reload success path separate.

## Concrete ownership transfer

Create one `lib/DisplayController.qml` child of the persistent Service.
Keep the existing directories, entry points, bridge identity and fixed scripts.
Do not pass the Service, a panel, a proxy or the shell QObject to the owner.

| Transfer from Service | Sole owner after M6 |
| --- | --- |
| `displayDraft`, `draftMode`, `draftSingleTarget`, `draftMirrorSource`, derived `draftEditable` | Display owner. Service retains compatible read-only data projections |
| `previewBusy`, `previewAbortReason`, `previewBaseline`, `previewBefore`, `previewApplied`, `previewObservedSignature`, `previewSeconds` | Display owner. Original per-window identities remain unchanged across re-edits |
| `pendingDisplayConfig`, `keepOptions`, `layoutWriteKind`, `keepFilesPending`, `keepSourceBaseline`, `keepDisableToggle` | Display owner. Capture accepted options before either candidate write |
| `candidateReady`, `plainCandidateReady`, `internalDisableSource`, `monitorsSource`, `monitorsLoaded` | Display owner. Source and acknowledgment handling move together |
| `previewApplyLua`, `previewApplyStaged`, `previewApplyExpectedOutputs`, `previewApplyFocusTarget`, `previewApplyActivateLua`, `previewApplyMigrateFirst`, `previewApplyPanelOrigin`, `previewApplyPanelTarget` | Display owner. Preserve each branch and its consumed-stage transition |
| `pendingRevertReason`, `pendingRevertPanelTarget`, `pendingRevertPanelOrigin`, `pendingRevertFocusTarget`, `pendingRevertActivateLua` | Display owner. No root handler independently resets these fields |
| `monitorsFile`, `internalDisableFile`, `candidateFile`, `plainCandidateFile` | Display owner. Preserve paths, atomic writes, watchers and signal order |
| `previewToken` FileView, `previewLoaded`, `previewFound` | Display owner. Service retains read-only startup gates |
| `previewArm` and `keepTransaction` Processes, including stderr collection | Display owner. Preserve their separate execution lanes and completion order |
| `previewCountdown` Timer | Display owner. Preserve its 1000 ms interval and 12-second countdown |

Transfer these complete function groups, with Service forwarding methods where needed:

- Drafts: `syncDisplayDraft`, `setDisplayValue`, `setResizedDisplayValue`,
  `setDisplayTransform`, `setDisplayPosition`, `setDisplayEnabled`, `displayEnabled`,
  `setModeValue` and `applyDisplaySetting`.
- Preview planning: `previewLayout`, `applyPreview`, `applyPreviewSnapshot`,
  `panelTransferTarget`, `previewFocusTarget`, `activationRule` and `stagePreviewApply`.
- Preview completion: `clearPreviewApplyStage`, `failPreviewApply`,
  `continuePreviewApply`, `finishPreviewApply` and `abandonPreview`.
- Revert: `revertPreview`, `continueRevertPreview`, and the preview-state cleanup
  currently inside `panelEvacuationTimedOut`.
- Persistence: `keepPreview`, `startKeepFiles`, `maybeStartKeep`, `keepFileFailed`,
  `restoreAppliedLayout`, `finishKeep`, `removeStationBlock` and `migrateMonitorPrecedence`.

Service retains these responsibilities:

- `state`, `gen`, `configGeneration`, `queuedStation`, expected events and both queues.
- Clients, monitors, lanes, assignments, current station and config/state persistence.
- `maybeStart`, `finishAuthorityMigration`, startup stale-token recovery and detached removal cleanup.
- `requestPanelEvacuation`, `acknowledgePanelEvacuation`, `clearPanelEvacuation`,
  the evacuation serial/fields, and the 2500 ms `panelEvacuationTimeout` Timer.
- `handleEvent`, `observeDesktop`, `monitorSignature`, `completeSnapshot`,
  `applyRuntime`, binds, screen-health recovery, window actions and panel intent.
- `swapRole`, `roleOf`, direction preferences and the bridge/IPC contract.

The retained `panelEvacuationTimedOut` entry becomes a scalar callback route.
It passes the current purpose and origin to the display owner. The owner performs
the existing preview/Revert cleanup through finite root ports. The root remains
the only writer of evacuation fields.

## Cross-owner writes that must become methods

These writes occur outside the main preview block at the reviewed revision.
Moving only that block would leave two writable preview owners.

| Existing caller | Required route |
| --- | --- |
| Workspace `restorePreviewBaseline(value)` callback in Service | Forward to display `restorePreviewBaseline(value)`. Restore/clear a detached value at the same load/commit boundary |
| Workspace `failPreview(message)` callback | Forward to display `failPreview(message)`. Clear busy, then use the existing Revert path |
| Workspace `finishPreviewApply()` callback | Keep root forwarding to display completion. Reuse the enclosing preview operation |
| `completeSnapshot` preview failure | Call display `failPreview(message)` instead of writing `previewBusy` on root |
| `updateAssignments` and monitor-source load | Call display `syncDisplayDraft()` at the existing observation boundary |
| `swapRole` Mirror branch | Call internal display `previewMirrorSource(name)` after saving lanes and synchronizing the draft |
| `ensureDirs` | Call display `reloadPreviewToken()` at the existing token-reload position |
| Root startup precedence migration | Forward to display `migrateMonitorPrecedence(done)`. Root retains the authority-version completion callback |
| Explicit block removal | Forward `removeStationBlock()`. Keep the existing `direct` transaction kind and return strings |
| Event and stable-preview observation | Forward `abandonPreview(reason)`. Never reconstruct or replay the cached preview target |

`previewMirrorSource` performs the existing source assignment and preview request
as one owner operation. It does not acquire lane ownership or add a UI action.
Root `targetMapping()` continues deriving the current target after fresh inputs.
It reads the compatible `previewApplied` projection during preview.

WorkspaceController keeps its journal and phase ownership. It receives detached
baseline data from the display projection. The display owner never writes the
journal, publishes a committed map or clears workspace phases.

## Finite data and effect surface

The names below describe internal ports. Public names and return strings stay compatible.
Stop and revise the packet if implementation needs broader root access.

| Direction | Data or port | Contract |
| --- | --- | --- |
| In | Existing state/candidate/plain/monitor/toggle paths | Validated fixed paths. No schema or filename changes |
| In | Operation state, root generations, startup state | Observation only. No second operation or configuration counter |
| In | Monitors, clients, lanes, current station | Read-only observations for the existing planners |
| In | Display preferences `{enabled, mode, singleTarget, mirrorSource}` | Root retains the config object and unrelated preferences |
| In | Committed map, pending flag, migration phase, topology-dirty flag | Read-only workspace projections |
| In | Panel wanted/screen and current shared error | Scalars only. No surface, delegate or proxy reference |
| Port | `beginPreview()`, `setOperationState(value)` | Preserve existing root arbitration and queue-clearing behavior |
| Port | `beginRevert()`, `invalidatePreviewOperation()` | Preserve the different existing generation increments. Do not replace them with generic `begin()` |
| Port | `refresh(includeClients, done)`, `evalLua(lua, done)`, `enqueue(argv, done)` | Existing queues, generation rejection and callback delivery |
| Port | `recordExpectedEvents(value)`, `monitorSignature()` | Publish expectations before effects and compare observed topology |
| Port | `reconcileWorkspace()`, `targetMapping()`, `clearWorkspaceTopologyDirty()` | Reconcile through M5. Clear dirty only after the existing fresh-snapshot barrier |
| Port | `requestPanelEvacuation(from, to, purpose)`, `clearPanelEvacuation()` | Root owns serial publication, acknowledgment validation and timeout |
| Port | `retainPanel(screen, until)` | Optional scalars preserve screen-only/deadline-only writes and their ordering |
| Port | `stopTopologyTimers()` | Stop removal grace and reload debounce at the existing edit boundary |
| Port | `publishDisplayOptions(options)`, `saveDisplayPreferences()` | Merge only accepted display options at the current publication point. Save after owner cleanup and source reload |
| Port | `invalidateAppliedBinds()`, `updateAssignments()`, `applyBinds()`, `applyRuntime()`, `armScreenHealthCheck()` | Preserve post-save/Revert restoration order without replaying monitor settings |
| Port | `launchWatchdog()` | Root launches the fixed 20-second detached template with the existing token path |
| Port | `reportError(message)`, `ready()`, `finishAuthorityMigration(done, reloadRequired)` | Shared error, startup readiness and one-time authority upgrade |
| Out | Existing draft, preview and source/load projections | Read-only or detached. Bridge snapshots retain the same data fields |
| Methods | Existing transferred methods and the narrow routes above | Forward compatible methods through Service. Add no IPC or bridge actions |

The owner controls the normal preview watchdog lifecycle through `launchWatchdog`.
Root bootstrap still handles a detected stale token before normal startup.
Root teardown still launches cleanup exactly once. Neither adds another preview owner.

Preserve command cancellation domains. Configuration generation retires queued
Lua commands but cannot cancel an already running effect. Preserve existing state
checks at callbacks. Do not introduce cancellation tokens or suppress completions.
Characterize stale callbacks before proposing any separate policy change.

## Required before/after traces

These source-derived traces specify required order. They are not hardware observations.
The extraction must match detailed effects and serialized bytes for each branch.

```text
Ordinary preview:
  validate -> retain first session baseline -> begin(previewing) -> pause countdown
  -> touch token through previewArm -> fresh clients -> capture original identities once
  -> launch detached watchdog -> choose position-only, mode-only, or full rules
  -> stage -> request evacuation if needed -> matching serial/output ack
  -> activate survivor if needed -> focus survivor -> publish expectations -> apply rules
  -> reconcile workspace -> journal ACK -> moves -> verification -> commit ACK
  -> restore focus -> renew token -> detached watchdog -> full 12-second countdown

Disabled-destination / migrate-first preview:
  same validation/token/staging/evacuation barriers
  -> enable destination with exact geometry -> focus destination
  -> migrate while both outputs remain -> journal/moves/verification/commit barriers
  -> finishPreviewApply consumes migrate-first flag before remaining monitor rules
  -> apply remaining rules -> fresh snapshot -> clear workspace topology dirty
  -> complete preview -> renew token/watchdog -> countdown

Re-edit:
  preserve previewBefore and original previewBaseline -> pause countdown -> retouch token
  -> plan from the last applied preview -> same safety/migration barriers
  -> renew countdown without replacing original window identities

Revert / countdown expiry:
  select saved survivor -> stage Revert -> evacuate panel -> matching ack
  -> enable saved survivor if needed -> focus survivor -> increment root operation gen
  -> applyingLayout -> remove token -> reload current saved configuration
  -> fresh snapshot -> rebuild draft -> reconcile using original identities
  -> restore binds/screen-health checks through the existing root callbacks

External reload / unexpected hotplug / stable-preview geometry change:
  root detects change -> stop countdown -> invalidate root operation/config generations
  -> clear evacuation/staging -> discard pending preview request, retain recovery baseline
  -> migrating if journal phase is active, otherwise idle -> remove token
  -> fresh snapshot -> adopt effective configuration -> reconcile identities
  -> never replay the abandoned monitor target
```

Wrong serial/output acknowledgments must dispatch nothing. Evacuation timeout must
not unlock destructive rules. Preserve the separate preview and Revert timeout paths.
Revert survivor-preparation failure retains the preview and resumes its countdown.
Snapshot, activation, focus, monitor-apply and token-renewal failures need separate traces.

### Persistence branches

| Branch | Required sequence and distinction |
| --- | --- |
| Ordinary preview Keep | Capture accepted options/source, stop countdown, stage both candidates, wait for changed-file acknowledgments, then run Keep |
| Scale/Resolution/Refresh | Idle-only. Generate and persist directly through Keep with kind `control`. No preview apply, token arm or countdown |
| Unchanged side control | Return `ok` without writing a candidate or applying monitor rules |
| Explicit block removal | Keep kind `direct`. Preserve its existing generated plain payload and options |
| Internal On + Keep | Only kind `preview` may capture the exact recognized Off flag. Compare both source files, suspend autoreload, save both and reload once |
| Candidate failure | Do not start Keep. Preserve the current branch-specific recovery, including reload for a failed preview save |
| Keep exit 3 or 4 | Preserve error reporting and fresh observed restoration. Never overwrite newer personal bytes |
| Keep success | Publish accepted options to root config, clear baseline/staging, reload the source FileView, save config, refresh observations, restore bookkeeping/binds |

Keep's eight positional arguments remain, in order:
`candidatePath`, `monitorsPath`, `plainCandidatePath`, `plainPath`, token path,
`keepSourceBaseline`, `internalDisablePath`, `keepDisableToggle`.
Preserve stderr collection and `finishKeep(code, errors)` delivery.

Unchanged candidate text is already ready. Changed text requires its real `saved`
signal. A candidate failure must not complete another write's barrier.
Preserve the template's existing one-second watched-apply check. This is not the
removed window-slider sleep. Successful ordinary display writes must not force
a second reload or replay unchanged monitor rules.

## Verification required before accepting M6

Implementation should proceed in these increments within the approved milestone:

1. Pin the pre-M6 production functions/signals and capture branch traces before transfer.
2. Add owner fixtures and explicit ports. Preserve every current regression assertion.
3. Transfer the entire preview state and its I/O callbacks without a second writable owner.
4. Adapt consumers through forwarding and detached projections. Re-run focused checks after each boundary change.
5. Compare traces, persisted bytes and rollback fixtures before the final milestone commit.

Retain coverage from `display-transaction`, `preview-service`, `preview-reedit`,
`panel-reopen`, `internal-monitor-toggle`, `recovery`, `system-authority`,
`migration-service`, `workspace-owner`, `grid`, `screen-health` and bridge tests.
Keep M2 compatibility tests and the actual fixed-template transaction tests.
Source guards may move to the new owner, but cannot replace behavioral assertions.

Add production QML-owner cases with delayed effects and fake compositor dispatch:

- Every trace branch above, including migrate-first and both Mirror source directions.
- Wrong/stale serials, wrong outputs, missing acknowledgments and both timeout paths.
- Both candidate acknowledgment orders, identical text, save failures and late signals.
- Re-edits, new clients, original baseline recovery and nested workspace completion.
- Queued stale generations, running-effect callbacks and external cancellation during migration.
- Keep completion through stderr/exit callbacks, overrides and failed fresh snapshots.
- Startup readiness, source reloads, stale-token recovery routing and single-owner teardown.

Use real Quickshell FileViews only with temporary source/candidate/token paths.
Double compositor dispatch, detached watchdog launch and transaction process effects
in the owner harness. Real fixed scripts may run only against temporary files and
fake desktop commands. Do not instantiate production Service in these tests.
Record actual signals, file bytes and any untested process-lifetime assumptions.

Verify the retained root panel barrier with the production owner and scalar ports.
Test root failure/event routes as well as isolated owner calls. Keep direct and
replacement-bar behavior compatible, including synchronous preview-busy publication.
No delayed callback may capture a widget-owned proxy or panel delegate.

Run the full portable suite, recursive QML compiler, theme scan, affected offscreen
checks and clean-export plugin validation. Verify all runtime QML is discovered.
Reject unexplained trace differences, lost assertions, broader dependency ports,
double writes or ambiguity about recovery. Do not claim isolated checks prove hardware.

## Rollback and hardware boundary

Rollback is a code revert to the reviewed pre-M6 implementation.
Keep journal/config schemas, marked sections, paths and script arguments unchanged.
Prove old/new recovery in both directions with temporary pending journals, preview
tokens and interrupted-save fixtures. Preserve current source comparison and
conditional rollback when external edits arrive during failure recovery.
Never reset the journal, delete backups or restore cached geometry over personal Lua.

The proposal's H1-H9 procedure remains the later hardware plan. It covers Keep,
Revert/timeout, Single/Mirror source changes, side controls, panel evacuation,
hotplug, re-edits, the internal Off flag and detached crash recovery.
Such runs require separate authorization, backups, identity/config/token evidence,
and restoration of the original desktop state. H9 requires explicit crash approval.
Normal shell restart is not that crash experiment.

Three/four-output, simultaneous dock, lid, suspend and cold-login limits remain.
No installation, desktop restart, live config/topology edit, dependency installation
or push is included in M6 implementation approval.

## Recorded decision

The user approved this transfer and verification strategy at the reviewed source
revision, with M2 retained and live work excluded. Implementation follows that
scope. Public APIs, scripts, persisted formats and timing defaults remain compatible.
The checkpoint records actual verification and its hardware limits.
