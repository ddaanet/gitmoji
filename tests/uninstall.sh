#!/usr/bin/env bash
# Integration test: /gitmoji:uninstall must complete using harness
# file-edit tools and a focused `rm`, not by shelling out to the bash
# uninstaller script. We deny `Bash(bash *)` to block that escape
# hatch; everything else is auto-approved (`bypassPermissions`).
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "$plugin_root/.test-uninstall-XXXXXX")"
trap 'rm -rf "$work"' EXIT

cd "$work"
git init -q
git config user.email test@example.com
git config user.name "Integration Test"

# Set up an installed state directly: write settings, copy hook files,
# chmod them executable. This is test scaffolding, not under test.
mkdir -p .claude
echo '{"gitmoji": {"enabled": true}}' | jq . > .claude/settings.json
cp "$plugin_root/scripts/gitmoji.sh"  .git/hooks/gitmoji.sh
cp "$plugin_root/scripts/gitmoji.cfg" .git/hooks/gitmoji.cfg
cat > .git/hooks/commit-msg <<'EOF'
#!/usr/bin/env bash
# gitmoji-plugin-installed
exec "$(dirname "$0")/gitmoji.sh" "$@"
EOF
chmod +x .git/hooks/commit-msg .git/hooks/gitmoji.sh

output=$(claude \
    --permission-mode bypassPermissions \
    --disallowedTools "Bash(bash *)" \
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

jq -e '.gitmoji.enabled == false' .claude/settings.json >/dev/null \
    || fail ".claude/settings.json missing gitmoji.enabled = false"

[ ! -f .git/hooks/commit-msg ]  || fail ".git/hooks/commit-msg was not removed"
[ ! -f .git/hooks/gitmoji.sh ]  || fail ".git/hooks/gitmoji.sh was not removed"
[ ! -f .git/hooks/gitmoji.cfg ] || fail ".git/hooks/gitmoji.cfg was not removed"

echo "PASS"
