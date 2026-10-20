# Automated checks

`.github/workflows/checks.yml` runs **Station portable checks** on pull requests
and pushes to `main` and `dev`, and supports manual dispatch. It uses an
ephemeral GitHub-hosted Ubuntu runner, read-only repository permissions, pinned
action revisions, and no repository secrets or persisted checkout credentials.
Do not run contributor pull requests on a runner attached to your desktop.

The job runs the Node regression suite (including the Lua and Perl helpers),
the theme-token scanner, and a whitespace check. The three installed-host M0
contract tests intentionally skip when Omarchy is absent. Passing this job
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
