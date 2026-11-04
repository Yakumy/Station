# Architecture implementation checkpoint

This checkpoint lets the maintainer or a later coding session resume the approved
[proposal](ARCHITECTURE-REFACTOR-PROPOSAL.md) without reconstructing the chat.

## Authorization and limits

The user authorized implementation and one commit per completed step on `dev`.
Do not push. Do not install an update or change the running desktop under this
scope. Preserve human review before M5 and before M6. M2 deletion requires its
cross-version and detached-recovery proof. M8 and M9 remain optional.

## Completed work

| Step | Commit / status | Evidence |
| --- | --- | --- |
| Proposal | `b5b946f` | Reviewed audit, compatibility gates and hardware checklist |
| M0 | `07016a1` | 266 Node cases passed, 25 QML components compiled, theme scan 44 files/0 violations, clean-export plugin validation passed |
| M1 | Included with this checkpoint's introducing commit | 267 Node cases passed, 25 QML components compiled, theme scan 45 files/0 violations. Key-picker pointer harness and 23 layout cases passed |

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

## Resume procedure

1. Read `AGENTS.md`, the proposal and this checkpoint.
2. Check `git status --short --branch` and `git log -5 --oneline`.
3. Preserve any work outside the next milestone.
4. Evaluate M2 compatibility before changing its writer or argument contract.
5. Continue M3/M4 if M2 must remain intact. Stop before M5 for its review packet.
6. Update this checkpoint and affected architecture/contracts with each step.
7. Inspect the complete and staged diff. Commit that step on `dev`. Do not push.

The installed plugin remains separate from this source checkout. A local commit
is not evidence that the running shell loaded it.
