## Current task

The commit-msg hook now skips messages git composed itself, so
`git merge` and `git subtree pull --squash` stop being rejected. What
remains is propagation: nothing outside this working tree has the fix
yet.

## Open decisions

- Whether to release now. The plugin is at `0.5.0` and the installed
  cache `~/.claude/plugins/cache/ddaanet/gitmoji/0.5.0` still holds the
  broken hook. `session-materialize.sh` copies from its own
  `script_dir`, so every other repo — `~/code/handoff` among them —
  re-materializes `0.5.0` at each SessionStart and keeps rejecting
  merges. Manually copying this working tree into another repo is
  self-reverting for the same reason. The durable fix is the release
  cascade: `just release patch --yes` (needs `--yes`, and
  `dangerouslyDisableSandbox` for the marketplace `mv`), then the
  version bump in `claude-plugins/.claude-plugin/marketplace.json`.
