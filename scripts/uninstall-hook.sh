#!/usr/bin/env bash
# Uninstall the gitmoji commit-msg hook from the current git repository.
# Only removes files marked as installed by this plugin.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    echo "not inside a git repository" >&2
    exit 1
fi

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

if [[ ! -f "$target" ]] || ! grep -q "$marker" "$target" 2>/dev/null; then
    echo "no gitmoji hook installed at $target" >&2
    exit 0
fi

rm -f "$target" "$hooks_dir/gitmoji.sh" "$hooks_dir/gitmoji.cfg"
echo "uninstalled commit-msg hook from $target"
