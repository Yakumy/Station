# Releasing

This page covers the installed plugin on the maintainer's machine, publishing, and
the marketplace. Do each only when the maintainer asks for it. Local work happens on
`dev`.

## Update the installed plugin

The source checkout and `~/.config/omarchy/plugins/yakumy.station` are separate Git
checkouts. The stock updater installs only committed source: it fetches the source
checkout's `HEAD` and runs `merge --ff-only`.

1. Finish and verify the source change with `python3 test/run.py all`.
2. Commit it. If the maintainer has not authorized a commit, ask. Do not copy
   uncommitted files into the installed checkout.
3. Check that the installed checkout is clean, on `dev`, with a `file://` origin:

   ```sh
   git -C ~/.config/omarchy/plugins/yakumy.station status --short --branch
   git -C ~/.config/omarchy/plugins/yakumy.station remote get-url origin
   ```

4. Update, and restart the shell once:

   ```sh
   omarchy plugin update yakumy.station --yes
   omarchy restart shell
   omarchy-shell shell ping
   ```

5. Compare both revisions and read `omarchy-shell yakumy.station status`.

Always restart after an update. A plugin rescan can leave an old component cached, and
`listPlugins` does not prove that the running panel uses the new code. If the panel
still shows old text, compare the installed files with the source and check the shell
process start time.

### After an amend

**Warning: never amend only to make an install convenient.** An amended commit
diverges, and the stock updater refuses it. If the maintainer requests both an amend
and an update:

1. Check that the installed checkout is clean with no unknown work, and has the
   expected origin.
2. Fetch the origin.
3. Move only the installed checkout's `dev` branch to the exact fetched commit.

Never delete or reclone the checkout, and never push from it.

## Publish

GitHub requires the `Station portable checks` status on `main`.

1. Check the worktree, fetch `origin` and inspect divergence.
2. Commit the reviewed work on `dev`.
3. Fast-forward local `main` from `dev`, then return to `dev`.
4. Run `git push origin dev`.
5. Wait for the `Station checks` run on that exact commit to succeed.
6. Run `git push origin main`. An atomic push of both refs before CI completes is
   rejected. Never force push.
7. Check the remote branch commits and the default-branch `HEAD`.

## Submit to the marketplace

Commit all notes before you submit, because validation binds the exact final commit.

1. Read the current
   [VERIFICATION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md)
   and `.github/ISSUE_TEMPLATE/verify-plugin.yml` in that repository.
2. Validate a clean export. `python3 test/run.py all` does this.
3. Search open issues for Station, to avoid a duplicate. Issue #6473 is obsolete, and
   #12370 is a past example.
4. Create an issue in `omacom/omarchy-plugin-marketplace`, titled
   `[Verify]: Station <manifest version> update`, with `gh issue create --body-file`.
   Use these exact headings, each followed by a blank line, and add nothing else. The
   parser rejects changes.

   ```markdown
   ### Verification action

   Verify and publish a newer upstream commit

   ### Plugin ID

   yakumy.station

   ### Repository URL

   https://github.com/Yakumy/Station

   ### Target commit

   <full 40-character published default-branch HEAD>

   ### Verification acknowledgment

   - [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.
   ```

   Include `### Standard installation acknowledgment` only when you request that form
   action. Do not add maintainer labels. Put release notes in a later comment.
5. Read the bot comments and linked Actions runs. Report the issue URL, target commit
   and validation state.

Submission is not approval. Publication requires marketplace review and the
`approved-and-verified` label. Do not claim publication until you confirm it.
