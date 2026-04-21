---
description: Uninstall the gitmoji commit-msg hook from the current git repository.
---

Opt this repository out of the gitmoji `commit-msg` hook.

Run:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-hook.sh
```

Behaviour:

- Sets `gitmoji.enabled: false` in project-scope `.claude/settings.json`
  (checked in opt-out, so the team inherits the decision via git).
- Tears down the per-repo hook immediately: removes the marker-tagged
  `commit-msg` wrapper and the copied `gitmoji.sh` / `gitmoji.cfg`.
- Leaves unrelated hooks alone (only touches files carrying the
  plugin-installed marker).

To opt out at user scope (every repo that doesn't explicitly opt back
in), set `gitmoji.enabled: false` in `~/.claude/settings.json`.
