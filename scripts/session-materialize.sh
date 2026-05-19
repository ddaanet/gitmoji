#!/usr/bin/env bash
# Materialize (install or refresh) the per-repo commit-msg hook from
# this invocation's plugin version. Runs on every SessionStart in
# repos where the plugin is enabled (resolved via Claude Code's
# enabledPlugins). When this script runs, the plugin is enabled here,
# so install unconditionally; never tear down. Refuses to overwrite a
# foreign commit-msg without the `gitmoji-plugin-installed` marker.
# Idempotent.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
repo_root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    exit 0
fi

hooks_dir="$repo_root/.git/hooks"
target="$hooks_dir/commit-msg"
marker="gitmoji-plugin-installed"

mkdir -p "$hooks_dir"
if [[ -f "$target" ]] && ! grep -q "$marker" "$target" 2>/dev/null; then
    echo "gitmoji: existing commit-msg hook at $target; leaving alone (move it to enable)" >&2
    exit 0
fi
cp "$script_dir/gitmoji.sh"  "$hooks_dir/gitmoji.sh"
cp "$script_dir/gitmoji.cfg" "$hooks_dir/gitmoji.cfg"
chmod +x "$hooks_dir/gitmoji.sh"
cp "$script_dir/commit-msg.template" "$target"
chmod +x "$target"
echo "gitmoji: materialized commit-msg hook at $target"
