#!/usr/bin/env bash
# Remove the per-repo gitmoji commit-msg hook from the current git
# repo. Refuses to touch a commit-msg hook that lacks the
# `gitmoji-plugin-installed` marker. Idempotent. No settings.json
# mutation — opt-in is owned by Claude Code's enabledPlugins, not by
# the plugin.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    echo "not inside a git repository" >&2
    exit 1
fi

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

if [[ -f "$target" ]] && grep -q "$marker" "$target" 2>/dev/null; then
    rm -f "$target" "$hooks_dir/gitmoji.sh" "$hooks_dir/gitmoji.cfg"
    echo "gitmoji: removed commit-msg hook at $target"
elif [[ -f "$target" ]]; then
    echo "gitmoji: existing commit-msg hook at $target lacks the plugin marker; leaving alone" >&2
    exit 0
else
    echo "gitmoji: no commit-msg hook at $target; nothing to do"
fi
