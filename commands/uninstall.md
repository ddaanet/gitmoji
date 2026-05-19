---
description: Uninstall the gitmoji commit-msg hook from the current git repository.
---

Uninstall the gitmoji `commit-msg` hook from the current repository.
Run this **before** disabling or uninstalling the gitmoji plugin — once
the plugin stops loading, there is no SessionStart event to clean up
after itself, and the hook files would persist in `.git/hooks/`.

## Steps

1. Operate on the current working directory. Confirm it is inside a
   git repository; if not, tell the user and stop.

2. Run the cleanup script with the Bash tool, passing
   `dangerouslyDisableSandbox: true`. The script writes to
   `.git/hooks/` which is outside the default sandbox; the auto-mode
   classifier auto-approves the bypass for plugin scripts writing to
   that directory.

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-hook.sh
   ```

3. Report the result to the user:
   - If the script printed `gitmoji: removed commit-msg hook at …`,
     tell the user the hook is gone and that commit messages in this
     repo will no longer be rewritten.
   - If it printed `gitmoji: existing commit-msg hook at … lacks the
     plugin marker`, tell the user a non-gitmoji `commit-msg` is
     present and was left untouched; they can move it manually if
     desired.
   - If it printed `gitmoji: no commit-msg hook at …`, tell the user
     there was nothing to remove.

## Why this shape

The opt-in mechanism for the plugin is Claude Code's
`enabledPlugins["gitmoji@ddaanet"]` (managed via `/plugin install`,
`/plugin uninstall`, the `/plugins` TUI, or hand-edit of
`.claude/settings.json`). The plugin never writes that key. This
slash command is the only verb the plugin owns — it removes the
materialized hook files so commit-message rewriting stops.

There is no matching `/gitmoji:install`. Installation is automatic:
when the plugin is enabled in a repo's scope chain, SessionStart
fires there and the materializer installs/refreshes the hook files.
