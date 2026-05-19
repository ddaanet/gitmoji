#!/usr/bin/env bash
# Integration test: /gitmoji:uninstall must remove the marker-tagged
# hook files from .git/hooks/ without modifying .claude/settings.json.
# The slash command shells to scripts/uninstall-hook.sh with
# dangerouslyDisableSandbox: true (auto-approved by the auto-mode
# classifier for plugin scripts writing .git/hooks/).
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "$plugin_root/.test-uninstall-XXXXXX")"
trap 'rm -rf "$work"' EXIT

cd "$work"
git init -q
git config user.email test@example.com
git config user.name "Integration Test"

# Set up an installed state directly. No settings.json — the new
# design does not use any plugin-owned settings key.
cp "$plugin_root/scripts/gitmoji.sh"           .git/hooks/gitmoji.sh
cp "$plugin_root/scripts/gitmoji.cfg"          .git/hooks/gitmoji.cfg
cp "$plugin_root/scripts/commit-msg.template"  .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg .git/hooks/gitmoji.sh

output=$(claude \
    --permission-mode bypassPermissions \
    --plugin-dir "$plugin_root" \
    --add-dir "$work" \
    --add-dir "$plugin_root" \
    -p "/gitmoji:uninstall" 2>&1) || status=$?
status=${status:-0}

fail() {
    echo "FAIL: $1" >&2
    echo "--- claude output ---" >&2
    echo "$output" >&2
    echo "--- end claude output ---" >&2
    exit 1
}

[ "$status" -eq 0 ] || fail "claude exited with status $status"

[ ! -f .git/hooks/commit-msg ]  || fail ".git/hooks/commit-msg was not removed"
[ ! -f .git/hooks/gitmoji.sh ]  || fail ".git/hooks/gitmoji.sh was not removed"
[ ! -f .git/hooks/gitmoji.cfg ] || fail ".git/hooks/gitmoji.cfg was not removed"

# Slash command must not have created or modified .claude/settings.json.
[ ! -f .claude/settings.json ] || fail ".claude/settings.json was written by the slash command"

echo "PASS"
