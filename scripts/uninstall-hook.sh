#!/usr/bin/env bash
# Remove the per-repo gitmoji commit-msg hook from the current git
# repo. Refuses to touch a commit-msg hook that lacks the
# `gitmoji-plugin-installed` marker. Idempotent. No settings.json
# mutation — opt-in is owned by Claude Code's enabledPlugins, not by
# the plugin.
set -euo pipefail

# rev-parse prints the common dir relative to the cwd or absolute;
# resolve it with cd/pwd rather than --path-format (git >= 2.31).
if ! common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"; then
    echo "not inside a git repository" >&2
    exit 1
fi
common_dir="$(CDPATH='' cd -- "$common_dir" && pwd)"

# The default hooks dir (shared by linked worktrees), regardless of
# core.hooksPath: it is the only place the plugin ever installs, so a
# hook left from before hooksPath was set is still removable.
hooks_dir="$common_dir/hooks"
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
