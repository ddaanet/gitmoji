---
description: Uninstall the gitmoji commit-msg hook from the current git repository.
---

Uninstall the gitmoji `commit-msg` hook from the current repository.
Use the `Read`, `Edit`, and `Bash` tools directly — do not shell out
to the bash uninstaller script.

## Steps

1. Operate on the current working directory. Assume `cwd` is the
   repository root; if it is not, ask the user to re-run from the
   root.

2. Update `.claude/settings.json`. If the file exists, use `Edit` to
   set `.gitmoji.enabled = false` while preserving every other key.
   If it does not exist, create `.claude/` and `Write`:

   ```json
   {
     "gitmoji": {
       "enabled": false
     }
   }
   ```

3. Tear down the per-repo hook **only if it carries the marker**.
   Read `.git/hooks/commit-msg`. If it exists and contains the literal
   string `gitmoji-plugin-installed`, run:

   ```
   rm -f .git/hooks/commit-msg .git/hooks/gitmoji.sh .git/hooks/gitmoji.cfg
   ```

   If `.git/hooks/commit-msg` exists but does **not** contain the
   marker, leave it alone (it was not installed by this plugin) and
   tell the user.

4. Tell the user the hook is disabled and removed. Conventional
   prefixes will no longer be rewritten on commit in this repo.

## Why this shape

`.claude/settings.json` is the source of truth — setting
`gitmoji.enabled` to `false` is what disables the hook for teammates
on their next session. The `.git/hooks/` files are a cache; removing
them is immediate cleanup. The plugin's `SessionStart` materializer
runs the same teardown on every session if `gitmoji.enabled` is
`false`, so any stale cache files on other clones get cleaned up
automatically.

## Scope overrides

To opt out for every repo, set `"gitmoji": {"enabled": false}` in
`~/.claude/settings.json`. To opt out for one user in one repo
without changing the team's checked-in setting, use
`.claude/settings.local.json`.
