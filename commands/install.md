---
description: Install the gitmoji commit-msg hook into the current git repository.
---

Install the gitmoji `commit-msg` hook in the current repository.

Run:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install-hook.sh
```

Behaviour:

- Locates the git repo root via `git rev-parse --show-toplevel`.
- Copies `gitmoji.sh` and `gitmoji.cfg` into `.git/hooks/`.
- Writes a `commit-msg` wrapper that invokes the copied `gitmoji.sh`.
- Refuses to overwrite an existing `commit-msg` hook unless it was
  previously installed by this plugin (detected via a marker comment).

After installation, conventional prefixes in commit messages are
translated to emojis at commit time: `feat: add X` becomes `✨ add X`.

See `${CLAUDE_PLUGIN_ROOT}/scripts/gitmoji.cfg` for the full prefix →
emoji mapping.
