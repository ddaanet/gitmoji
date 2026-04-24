#!/usr/bin/env bash
# Opt this repo out of the gitmoji commit-msg hook by setting
# `gitmoji.enabled = false` in project-scope .claude/settings.json, then
# tearing down the per-repo hook immediately. Leaves unrelated hooks
# alone (only removes files carrying the plugin-installed marker).
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    echo "gitmoji: jq is required (used to edit settings.json)" >&2
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    echo "not inside a git repository" >&2
    exit 1
fi

settings="$repo_root/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
# Stage next to the target so `mv` stays on one filesystem and resolves
# to rename(2) — atomic even when Claude Code holds settings.json open.
tmp="$(mktemp "$settings.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
if [[ -f "$settings" ]]; then
    jq '.gitmoji.enabled = false' "$settings" > "$tmp"
else
    jq -n '{gitmoji: {enabled: false}}' > "$tmp"
fi
mv "$tmp" "$settings"
echo "set gitmoji.enabled = false in $settings"

CLAUDE_PROJECT_DIR="$repo_root" bash "$script_dir/session-materialize.sh"
