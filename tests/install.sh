#!/usr/bin/env bash
# Integration test: /gitmoji:install must complete using harness
# file-write tools (Edit/Write/Read), not by shelling out to the bash
# installer script. We deny `Bash(bash *)` to block that escape hatch;
# everything else is auto-approved (`bypassPermissions`). The old
# bash-based slash command can't invoke its script and fails; the new
# Edit/Write-based command succeeds.
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "$plugin_root/.test-install-XXXXXX")"
trap 'rm -rf "$work"' EXIT

cd "$work"
git init -q
git config user.email test@example.com
git config user.name "Integration Test"

output=$(claude \
    --permission-mode bypassPermissions \
    --disallowedTools "Bash(bash *)" \
    --plugin-dir "$plugin_root" \
    --add-dir "$work" \
    --add-dir "$plugin_root" \
    -p "/gitmoji:install" 2>&1) || status=$?
status=${status:-0}

fail() {
    echo "FAIL: $1" >&2
    echo "--- claude output ---" >&2
    echo "$output" >&2
    echo "--- end claude output ---" >&2
    exit 1
}

[ "$status" -eq 0 ] || fail "claude exited with status $status"

[ -f .claude/settings.json ] \
    || fail ".claude/settings.json was not created"
jq -e '.gitmoji.enabled == true' .claude/settings.json >/dev/null \
    || fail ".claude/settings.json missing gitmoji.enabled = true"

[ -f .git/hooks/commit-msg ] \
    || fail ".git/hooks/commit-msg was not created"
grep -q "gitmoji-plugin-installed" .git/hooks/commit-msg \
    || fail ".git/hooks/commit-msg missing the plugin marker"
[ -x .git/hooks/commit-msg ] \
    || fail ".git/hooks/commit-msg is not executable"

[ -f .git/hooks/gitmoji.sh ]  || fail ".git/hooks/gitmoji.sh missing"
[ -f .git/hooks/gitmoji.cfg ] || fail ".git/hooks/gitmoji.cfg missing"
[ -x .git/hooks/gitmoji.sh ]  || fail ".git/hooks/gitmoji.sh not executable"

# End-to-end smoke: the installed hook should rewrite a commit message.
msg=$(mktemp -p "$work")
echo "feat: integration test" > "$msg"
.git/hooks/commit-msg "$msg" || fail "installed hook failed on a sample message"
result=$(cat "$msg")
[ "$result" = "✨ integration test" ] \
    || fail "hook produced '$result', expected '✨ integration test'"

echo "PASS"
