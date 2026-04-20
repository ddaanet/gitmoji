---
description: Uninstall the gitmoji commit-msg hook from the current git repository.
---

Remove the gitmoji `commit-msg` hook (and the copied `gitmoji.sh` /
`gitmoji.cfg`) from the current git repository.

Run:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-hook.sh
```

Only removes files marked as installed by this plugin. Leaves unrelated
hooks alone.
