#!/usr/bin/env bash
# Opt this repo in to the gitmoji commit-msg hook by writing
# `gitmoji.enabled = true` into project-scope .claude/settings.json, then
# materializing the hook immediately. Settings is the source of truth —
# the plugin's SessionStart hook keeps .git/hooks/ in sync on every
# session (so plugin upgrades propagate transparently).
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
tmp="$(mktemp)"
if [[ -f "$settings" ]]; then
    jq '.gitmoji.enabled = true' "$settings" > "$tmp"
else
    jq -n '{gitmoji: {enabled: true}}' > "$tmp"
fi
mv "$tmp" "$settings"
echo "set gitmoji.enabled = true in $settings"

CLAUDE_PROJECT_DIR="$repo_root" bash "$script_dir/session-materialize.sh"
