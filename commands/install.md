---
description: Install the gitmoji commit-msg hook into the current git repository.
---

Install the gitmoji `commit-msg` hook in the current repository by
writing `.claude/settings.json` and materializing the per-repo hook
files. Use the `Read`, `Edit`, and `Write` tools directly — do not
shell out to the bash installer script.

## Steps

1. Operate on the current working directory. Assume `cwd` is the
   repository root; if it is not, ask the user to re-run from the
   root.

2. Update `.claude/settings.json`. If the file exists, use `Edit` to
   set `.gitmoji.enabled = true` while preserving every other key.
   If it does not exist, create `.claude/` and `Write` exactly:

   ```json
   {
     "gitmoji": {
       "enabled": true
     }
   }
   ```

3. Check `.git/hooks/commit-msg`. If it exists and does **not**
   contain the literal string `gitmoji-plugin-installed`, stop and
   tell the user to move or remove the existing hook before
   re-running.

4. Materialize the hook files in `.git/hooks/`. For each, `Read` the
   source from `${CLAUDE_PLUGIN_ROOT}/scripts/` and `Write` it
   **verbatim** (do not retype — shell metacharacters like `$0` and
   `$@` must round-trip exactly):
   - `scripts/gitmoji.sh` → `.git/hooks/gitmoji.sh`
   - `scripts/gitmoji.cfg` → `.git/hooks/gitmoji.cfg`
   - `scripts/commit-msg.template` → `.git/hooks/commit-msg` (this
     file carries the `gitmoji-plugin-installed` marker the
     materializer looks for; it must not be edited)

5. Run `chmod +x .git/hooks/commit-msg .git/hooks/gitmoji.sh` to make
   the hook scripts executable. This is the only Bash call required.

6. Tell the user the hook is installed: conventional prefixes
   (`feat:`, `fix:`, etc.) will now be rewritten to gitmoji emojis on
   commit. See `${CLAUDE_PLUGIN_ROOT}/scripts/gitmoji.cfg` for the
   full prefix → emoji mapping.

## Why this shape

`.claude/settings.json` is the source of truth — the `gitmoji.enabled`
setting, not files in `.git/hooks/`, decides whether the hook runs.
Writing it travels with the repo via git, so teammates inherit the
opt-in. The `.git/hooks/` files are a cache: the plugin's
`SessionStart` hook regenerates them from the current plugin version
on every session, so plugin upgrades land without per-repo work.

## Scope overrides

`gitmoji.enabled` resolves from Claude Code's settings hierarchy —
more specific wins:

1. `.claude/settings.local.json` (per-user, gitignored)
2. `.claude/settings.json` (checked in) — where this command writes
3. `~/.claude/settings.json` (user defaults)

To opt in user-wide, set `"gitmoji": {"enabled": true}` in
`~/.claude/settings.json`. To opt out for a single repo, set it to
`false` in `.claude/settings.local.json`.
