---
description: Install the gitmoji commit-msg hook into the current git repository.
---

Opt this repository in to the gitmoji `commit-msg` hook.

Run:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hook.sh
```

Behaviour:

- Writes `gitmoji.enabled: true` into project-scope
  `.claude/settings.json` (checked in, so the whole team opts in via
  git).
- Materializes the hook immediately: copies `gitmoji.sh` / `gitmoji.cfg`
  into `.git/hooks/` and writes a marker-tagged `commit-msg` wrapper.
- Refuses to overwrite an existing `commit-msg` hook that lacks the
  marker (move or remove it first).

The plugin's SessionStart hook re-runs the materializer on every Claude
Code session, re-materializing `.git/hooks/` from the plugin's current
version. Plugin upgrades propagate to every installed repo on the next
session, no per-repo reinstall.

### Scope overrides

`gitmoji.enabled` is read from Claude Code's settings hierarchy — more
specific wins:

1. `.claude/settings.local.json` (this repo, per-user, gitignored)
2. `.claude/settings.json` (this repo, checked in) — where `/install` writes
3. `~/.claude/settings.json` (your user defaults, every repo)

To opt in user-wide for every repo, add `"gitmoji": {"enabled": true}`
to `~/.claude/settings.json`. To opt out locally, set it to `false` in
`.claude/settings.local.json`.

After installation, conventional prefixes in commit messages are
translated to emojis at commit time: `feat: add X` becomes `✨ add X`.

See `${CLAUDE_PLUGIN_ROOT}/scripts/gitmoji.cfg` for the full prefix →
emoji mapping.
