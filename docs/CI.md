# Automated checks

`.github/workflows/checks.yml` runs **Station portable checks** on pull requests
and pushes to `main` and `dev`, and supports manual dispatch. It uses an
ephemeral GitHub-hosted Ubuntu runner, read-only repository permissions, pinned
action revisions, and no repository secrets or persisted checkout credentials.
Do not run contributor pull requests on a runner attached to your desktop.

The job runs the Node regression suite (including the Lua and Perl helpers),
the theme-token scanner, and a whitespace check. Four installed-host cases intentionally skip when Omarchy is absent: three M0
contracts and the internal-toggle command contract. Passing this job
does not prove QML compilation, final rendering, or physical monitor behavior.
Run the Omarchy-specific checks in AGENTS.md locally before releasing.

After this workflow is published and has a successful GitHub run, add
`Station portable checks` as a required status check for `main`, with the
branch required to be up to date. Keep pull requests and conversation
resolution required, force pushes and deletion disabled, and the required
approval count at zero for a solo maintainer. Apply these rules to admins.

The workflow file alone does not activate required status checks. Configure
the GitHub branch rule after the first run so it uses the actual reported job
name. This avoids requiring a check that has never been published.

Marketplace verification remains a separate process tied to the final release
commit, including any manifest version change.

The QML compiler supports `python3 tools/v2/check-qml.py . --list` without a
session. Compilation includes manifest entries, root QML and recursive runtime
subtrees. Theme scanning covers root sources, libraries and runtime assets. Only
the two approved logo SVG paths have branding exclusions in repository mode.

Persistent owner checks are local offscreen Qt harnesses:
`python3 tools/v2/check-bar-settings.py` and
`python3 tools/v2/check-window-settings.py`. The window harness uses the production
owner and proxy with doubled FileView I/O and queue effects. It checks synchronous
busy publication, readback settlement, file-event wiring and stale-read rejection.
`python3 tools/v3/check-window-sliders.py` checks the production tab and installed
slider with pointer events. These harnesses do not run in the portable GitHub job
and do not prove physical pointer or compositor behavior.
